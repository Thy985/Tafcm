/// TC-ARCH-MODEL-4: 颜色令牌守门 —— presentation 核心目录禁 `Colors.*` 直写。
///
/// 落地 UI_FIX_PLAN §3.5（P3 颜色语义化长期治理）"先立规矩"入口：
/// 断言 `lib/presentation/{screens,widgets,blocks,panels}` 与同类
/// `components/` 目录禁止 `Colors.(grey|black|white|blue|red|green|amber|
/// orange|yellow)` 直写，应改走 `EditorTokens` / `AppColors` / `AppSpacing`
/// 令牌，保证主题切换（light/dark/sepia）时不破版。
///
/// **allowlist 收紧机制**：初始 `knownOffenders` = 当前所有命中点（origin/main
/// 基线，2026-08-02）。P3 治理逐文件迁移时，每清除一行就从 allowlist 移除
/// 对应 `path:line`；新增 `Colors.*` 直写会被守门拦截。完成标准见 UI_FIX_PLAN
/// §6 DoD #7 + §3.5"完成标准"。
///
/// **允许项**：
/// - `Colors.transparent`：无色语义，token 系统不为其专设令牌；
/// - `Color(0x...)` 硬编码：属另一类技术债，不在本守门范围（待单独守门）。
///
/// **已知局限**：仅检测直写 `Colors.xxx`，以下模式漏报：
/// - 间接引用（`final c = Colors.grey;` 后使用 `c`）
/// - 解构（`final {foreground} = Colors;`）
/// - 常量别名（`const kDivider = Colors.grey;` 在 lib/ 外定义后引用）
library;

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TC-ARCH-MODEL-4 presentation 禁 Colors.* 直写', () {
    test('lib/presentation/{screens,widgets,blocks,panels,components} 无新增 Colors.* 直写', () {
      // 已知豁免（origin/main 基线，2026-08-02）：
      // - widgets/editor_bottom_bar.dart → 4 处 Colors.white（白底黑字容器，
      //   P3 迁移目标：改走 EditorTokens.surface / onSurface）
      // - widgets/formula_insert_dialog.dart → 7 处 Colors.white/grey/black
      //   （isDark 三元分支，P3 迁移目标：改走 EditorTokens 主题字段）
      // - widgets/preview_content.dart / markdown_input_field.dart / 等 →
      //   isDark 三元分支 Colors.grey[xxx]（同上）
      // - widgets/buttons.dart:117 → `const thumbColor = Colors.white` 带
      //   注释 `// tokens.toggle.thumbColor = #FFFFFF`，已对齐 token 字面值
      //   （tokens.json toggle.thumbColor = #FFFFFF）；P3 收尾时若 tokens
      //   扩展 thumbColor 字段则改走令牌，否则保留。
      // - components/loading.dart → 6 处 Colors.grey/red（错误状态色）
      // - components/bottom_sheet.dart:27 → Colors.grey[300]（拖拽指示色）
      // - blocks/paragraph/paragraph_block.dart:181 → Colors.grey.shade200
      //   （代码块底色，P3 迁移目标：codeBackground 令牌）
      //   P0-1（2026-08-29）：行内渲染提取到 blocks/shared/inline_spans.dart:62，
      //   allowlist 随迁移同步（同一处既有豁免，未新增）。
      const knownOffenders = <String>[
        'lib/presentation/blocks/shared/inline_spans.dart:62',
        'lib/presentation/components/bottom_sheet.dart:27',
        'lib/presentation/components/loading.dart:104',
        'lib/presentation/components/loading.dart:112',
        'lib/presentation/components/loading.dart:122',
        'lib/presentation/components/loading.dart:20',
        'lib/presentation/components/loading.dart:51',
        'lib/presentation/components/loading.dart:58',
        'lib/presentation/widgets/buttons.dart:117',
        'lib/presentation/widgets/editor_bottom_bar.dart:27',
        'lib/presentation/widgets/editor_bottom_bar.dart:43',
        'lib/presentation/widgets/editor_bottom_bar.dart:58',
        'lib/presentation/widgets/editor_bottom_bar.dart:65',
        'lib/presentation/widgets/export_menu.dart:51',
        'lib/presentation/widgets/formula_insert_dialog.dart:126',
        'lib/presentation/widgets/formula_insert_dialog.dart:132',
        'lib/presentation/widgets/formula_insert_dialog.dart:166',
        'lib/presentation/widgets/formula_insert_dialog.dart:200',
        'lib/presentation/widgets/formula_insert_dialog.dart:241',
        'lib/presentation/widgets/formula_insert_dialog.dart:261',
        'lib/presentation/widgets/formula_insert_dialog.dart:76',
        'lib/presentation/widgets/list_renderer.dart:152',
        'lib/presentation/widgets/markdown_input_field.dart:153',
        'lib/presentation/widgets/markdown_input_field.dart:74',
        'lib/presentation/widgets/markdown_input_field.dart:78',
        'lib/presentation/widgets/paragraph_renderer.dart:128',
        'lib/presentation/widgets/preview_content.dart:123',
        'lib/presentation/widgets/preview_content.dart:124',
        'lib/presentation/widgets/preview_content.dart:134',
        'lib/presentation/widgets/preview_content.dart:40',
        'lib/presentation/widgets/template_selector.dart:50',
        'lib/presentation/widgets/task_list_item_renderer.dart:29',
      ];
      final hits = <String>[];
      const scopes = <String>[
        'lib/presentation/screens',
        'lib/presentation/widgets',
        'lib/presentation/blocks',
        'lib/presentation/panels',
        'lib/presentation/components',
      ];
      final pattern =
          RegExp(r'\bColors\.(grey|black|white|blue|red|green|amber|orange|yellow)\b');
      for (final scope in scopes) {
        final dir = Directory(scope);
        if (!dir.existsSync()) continue;
        for (final entity in dir.listSync(recursive: true)) {
          if (entity is! File || !entity.path.endsWith('.dart')) continue;
          final lines = entity.readAsLinesSync();
          for (var i = 0; i < lines.length; i++) {
            final line = lines[i];
            final trimmed = line.trim();
            if (trimmed.startsWith('//') || trimmed.startsWith('*')) continue;
            // 截掉行内注释（URL 中的 // 不会有 Colors.，安全）
            final code = line.split('//')[0];
            if (!pattern.hasMatch(code)) continue;
            final key = '${entity.path.replaceAll("\\", "/")}:${i + 1}';
            if (knownOffenders.contains(key)) continue;
            hits.add('$key:${line.trim()}');
          }
        }
      }
      expect(
        hits,
        isEmpty,
        reason: 'UI_FIX_PLAN §3.5：presentation 核心目录禁止 Colors.* 直写，'
            '应改走 EditorTokens / AppColors 令牌。\n'
            '命中（新增或迁移后未同步 allowlist）：\n${hits.join("\n")}',
      );
    });
  });
}
