/// TC-ARCH-MODEL-5：Block 类型扩展克制守门（ADR-0020 D6）。
///
/// **铁律**：Block 类型（语义单元）的增加必须由**真实编辑语义**驱动，禁止由
/// **渲染 / 视觉需求**驱动。具体落到类名：任何 Block 类（表现层 `*Block extends
/// Widget`，或模型层 `*Element extends DocumentElement`）的名称若含渲染语义词
/// （颜色 / 尺寸 / 高亮等表现属性），视为「渲染驱动类型」反例，除非该类在 dartdoc
/// 中提供 `semantic_reason:` 说明，或所在文件登记了 ADR 引用（如 `ADR-0020`），
/// 证明其承载区别于现有类型的独立编辑行为（split / merge / selection / serialize）。
///
/// **目的**：阻止未来开发者新增 `RedBlock` / `BlueHighlightBlock` / `ColorBlock` /
/// `LargeTextBlock` / `FontSizeBlock` 这类错误抽象，避免 AST 因表现属性爆炸、
/// 维护成本失控（ADR-0020 D6 反例）。
///
/// **扫描范围**：
/// - `lib/presentation/blocks/**`：`class XxxBlock extends (Stateful|Stateless)Widget`
/// - `lib/data/models/**`：`class XxxElement extends DocumentElement`
/// - 兜底：`class XxxBlock extends DocumentElement`（跨层误命名）
///
/// **当前状态**：代码库现有 Block 类型（Heading / Paragraph / Quote / Table /
/// Code / Formula / Mermaid 等）均不含渲染语义词，故本守门**默认通过**——它是
/// 前向防御：一旦有人新增 `ColorBlock` 等类名且无 `semantic_reason:` / ADR 登记，
/// 本测试立即 fail 并给出修复指引。
///
/// 详见 ADR-0020 §2 D6 与 §4 / §5（TC-ARCH-MODEL-5 / M7）。
library;

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // 渲染语义词（大小写不敏感）：颜色 / 尺寸 / 高亮等表现属性词根。
  // 这些词根出现在 Block 类名中，通常意味着「为视觉差异新增类型」而非「为编辑
  // 语义新增类型」。
  final renderToken = RegExp(
    r'(color|red|blue|green|yellow|cyan|purple|orange|pink|gray|grey|'
    r'black|white|magenta|teal|highlight|size|large|small|big|tiny|huge|'
    r'fontsize|background|bg)',
    caseSensitive: false,
  );

  // 三类待检「Block 类型」声明。
  final blockWidgetClass = RegExp(
    r'class\s+(\w*Block)\s+extends\s+(?:StatefulWidget|StatelessWidget)\b',
  );
  final elementClass = RegExp(
    r'class\s+(\w*Element)\s+extends\s+DocumentElement\b',
  );
  final blockElementClass = RegExp(
    r'class\s+(\w*Block)\s+extends\s+DocumentElement\b',
  );

  // 查找类声明前的 dartdoc 是否含 `semantic_reason:`，或全文是否登记 ADR。
  // 任一满足即视为「已登记语义理由」，放行该渲染命名类（属刻意、受治理的例外）。
  String? reasonFor(List<String> lines, int classIdx) {
    // 向上扫描紧贴 class 的 dartdoc 块（允许 doc 与 class 间空一行）。
    for (var j = classIdx - 1; j >= 0; j--) {
      final t = lines[j].trim();
      if (t.startsWith('///')) {
        if (t.toLowerCase().contains('semantic_reason')) return 'dartdoc';
        continue;
      }
      if (t.isEmpty && (classIdx - j) <= 2) continue; // doc 与 class 间空行
      break; // 文档块结束
    }
    // 文件级 ADR 登记（该文件处于 ADR 治理下，新类型属受审例外）。
    final fileText = lines.join('\n');
    if (RegExp(r'ADR-\d{3,4}', caseSensitive: false).hasMatch(fileText)) {
      return 'ADR';
    }
    return null;
  }

  test('Block 类型禁止由渲染语义词驱动（TC-ARCH-MODEL-5 / ADR-0020 D6）', () {
    final violations = <String>[];
    const scanRoots = [
      'lib/presentation/blocks',
      'lib/data/models',
    ];
    for (final root in scanRoots) {
      final directory = Directory(root);
      if (!directory.existsSync()) continue;
      for (final entity in directory.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final path = entity.path.replaceAll('\\', '/');
        final lines = entity.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          final trimmed = line.trim();
          // 跳过注释行，避免匹配被注释掉的旧声明。
          if (trimmed.startsWith('//') || trimmed.startsWith('*')) continue;

          String? className;
          if (blockWidgetClass.firstMatch(line) case final RegExpMatch m) {
            className = m.group(1);
          } else if (elementClass.firstMatch(line) case final RegExpMatch m) {
            className = m.group(1);
          } else if (blockElementClass.firstMatch(line) case final RegExpMatch m) {
            className = m.group(1);
          }
          if (className == null) continue;
          if (!renderToken.hasMatch(className)) continue;

          // 命中渲染语义命名 → 必须有语义理由 / ADR 登记，否则记违规。
          final reason = reasonFor(lines, i);
          if (reason == null) {
            violations.add(
              '$path:${i + 1}: class $className 含渲染语义词，'
              '须提供 semantic_reason: 或登记 ADR',
            );
          }
        }
      }
    }

    expect(
      violations,
      isEmpty,
      reason: 'ADR-0020 D6：Block 类型不得由渲染/视觉需求驱动。\n'
          '若确有独立编辑语义，请在类 dartoc 写 `semantic_reason:` 或在文件中登记 ADR。\n'
          '命中（应改名或用「同类型 Block + 样式/inline mark」表达）：\n'
          '${violations.join('\n')}',
    );
  });
}
