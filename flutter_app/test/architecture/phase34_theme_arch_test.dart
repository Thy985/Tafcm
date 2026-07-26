/// Phase 3.4 Slice 3 / ADR-0015：主题迁移架构守门（grep gate）。
///
/// 落地 q-0 评审结论「现在最应该补的不是代码，而是验证门」：
/// - **TC-THEME-NO-STATIC-COLOR**：`lib/presentation/blocks/` 内禁止对
///   *主题相关颜色* token 做静态访问（如 `EditorTokens.textPrimary`）——
///   这类硬编码会绕过 ThemeExtension，主题切换时不生效。必须走
///   `EditorTokens.of(context).textPrimary`。
/// - **允许**：`EditorTokens.of(context).<color>`（运行时按主题取值）、
///   布局常量静态访问（`EditorTokens.blockRadius` 等，主题无关）、
///   `EditorTokens.linkColor`（TextSpan 边界，ADR-0015 已知豁免）。
/// - **迁移已发生正向断言**：blocks/ 必须确有若干 `.of(context)` 调用，
///   防止「颜色被整体删掉」而非「被迁移」造成的假通过。
///
/// 测试方式：源码静态扫描（与其余架构守门测试风格一致）。
library;

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// 主题相关颜色 token（[EditorTokens] 的 9 个实例字段）。
/// 这些**只能**经 of(context) 取；静态访问视为违规。
const _themeableColors = <String>[
  'textPrimary',
  'textSecondary',
  'borderFocused',
  'borderDefault',
  'codeBackground',
  'codeLanguageChip',
  'quoteBorderColor',
  'tableBorderColor',
  'tableHeaderBackground',
];

/// 递归收集目录下所有 .dart 文件。
List<File> _dartFilesUnder(String dirPath) {
  final dir = Directory(dirPath);
  if (!dir.existsSync()) return const [];
  return dir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();
}

void main() {
  group('TC-THEME-NO-STATIC-COLOR：blocks/ 禁止主题色静态访问', () {
    final blockFiles = _dartFilesUnder('lib/presentation/blocks');

    test('blocks/ 目录存在且含 .dart 文件', () {
      expect(blockFiles, isNotEmpty,
          reason: 'lib/presentation/blocks 应存在渲染组件');
    });

    test('无任何 EditorTokens.<themeableColor> 静态访问', () {
      final violations = <String>[];
      // 匹配 `EditorTokens.<color>`，但因 of(context) 形式为
      // `EditorTokens.of(context).<color>`（token 前是 `).` 而非 `EditorTokens.`），
      // 该正则天然只命中静态直取，放行 of(context) 链式取值。
      final pattern = RegExp(
        r'EditorTokens\.(' + _themeableColors.join('|') + r')\b',
      );

      for (final file in blockFiles) {
        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          if (line.trimLeft().startsWith('//')) continue; // 跳过整行注释
          if (pattern.hasMatch(line)) {
            violations.add('${file.path}:${i + 1}: ${line.trim()}');
          }
        }
      }

      expect(
        violations,
        isEmpty,
        reason: '以下位置对主题色做了静态访问，主题切换将失效，'
            '请改为 EditorTokens.of(context).<color>：\n${violations.join('\n')}',
      );
    });

    test('迁移已发生：blocks/ 确有 EditorTokens.of(context) 调用', () {
      var ofCount = 0;
      final ofPattern = RegExp(r'EditorTokens\.of\(');
      for (final file in blockFiles) {
        ofCount += ofPattern.allMatches(file.readAsStringSync()).length;
      }
      expect(
        ofCount,
        greaterThanOrEqualTo(10),
        reason: 'blocks/ 应存在足量 of(context) 取色（预期 14 处），'
            '当前仅 $ofCount，疑似颜色被删除而非迁移',
      );
    });

    test('linkColor 静态访问被豁免（TextSpan 边界，ADR-0015）', () {
      // 该断言仅为文档化豁免边界：linkColor 允许静态访问，
      // grep gate 的 _themeableColors 清单不包含 linkColor。
      expect(_themeableColors.contains('linkColor'), isFalse,
          reason: 'linkColor 属 TextSpan 已知边界，不纳入禁止清单');
    });
  });

  group('风险2 守门：darkModeProvider 降级为只读派生', () {
    test('editor_providers.dart 中 darkModeProvider 为 Provider<bool>（无 notifier）', () {
      final content =
          File('lib/providers/editor_providers.dart').readAsStringSync();
      expect(
        content.contains('final darkModeProvider = Provider<bool>('),
        isTrue,
        reason: 'darkModeProvider 应降级为只读派生 Provider<bool>，'
            'themeModeProvider 为唯一真源',
      );
      // 兼容迁移：必须保留旧键读取逻辑。
      expect(content.contains("'pref_dark_mode'"), isTrue,
          reason: '必须兼容迁移旧 pref_dark_mode 布尔键');
      expect(content.contains("'pref_theme_mode'"), isTrue,
          reason: '新三值主题应持久化到 pref_theme_mode');
    });

    test('providers.dart 不再重复定义 darkModeProvider / sharedPreferencesProvider', () {
      final content = File('lib/providers/providers.dart').readAsStringSync();
      expect(content.contains('darkModeProvider ='), isFalse,
          reason: 'AGENTS §3.2：darkModeProvider 应收敛到 editor_providers.dart 唯一定义');
      expect(content.contains('sharedPreferencesProvider ='), isFalse,
          reason: 'AGENTS §3.2：sharedPreferencesProvider 应收敛到 editor_providers.dart 唯一定义');
    });
  });
}
