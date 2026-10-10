/// TC-ARCH-MODEL-1: AST 单一真相源守门 —— presentation 禁直读 Document.content。
///
/// 落地 ADR-0020 Decision 1：Document.content 仅被 MarkdownParser（加载方向）
/// 读取；UI / 搜索 / 预览必须经 Repository 或 serializer 获取内容。
///
/// **已知局限**：仅检测直接引用 `doc.content` / `document.content`，以下模式漏报：
/// - 间接引用（`final c = doc.content;` 后使用 `c`）
/// - 解构（`final {content} = document;`）
/// - getter 封装（`String get body => document.content;`）
library;

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TC-ARCH-MODEL-1 presentation 禁直读 Document.content', () {
    test('lib/presentation/ 不直接访问 doc.content / document.content', () {
      // 已知豁免：
      // - editor_page.dart → MarkdownParser.parse(doc.content) 为加载方向
      // - file_manager_screen.dart / home_screen.dart → 从 documentListProvider
      //   stream 获取的 Document 对象上提取预览文本（数据经 Repository→Provider→Widget）
      const knownOffenders = <String>[
        // 行号维护史：#323 导出 BACK 拦截接线（+1 行）139→140；
        // merge main（#352 resume 守护接线 +6 行）140→146；
        // #333 接线（persistCallback +2 行）146→147；
        // #330 压缩 _loadFromFile 注释（-2 行）147→145。
        // 违规行为未变（MarkdownParser.parse 加载方向豁免），仅位置维护。
        'lib/presentation/editor/editor_page.dart:145',
        // #338：AppBar 补搜索/导入/新建入口（+20 行）128→148。违规行为未变，仅位置维护。
        'lib/presentation/screens/file_manager_screen.dart:148',
        // 行号维护史：#242 删搜索按钮（-11 行）282→269；P0-1 补回 onSearch 字段
        // 与注释（+10 行）269→279，注意该 commit 声称「按钮恢复」但 Icons.search
        // 从未重新渲染，故 #242 的关闭理由不成立（详见 #338）；
        // merge origin/main（#283 入口删除冲突消解）→272；
        // #333-C 同名消歧（+1 行，274 前插 subtitle 计算）272→273；
        // #330 _openAnyMd 只读说明注释（+2 行）273→275；
        // #338 抽 doc_actions.dart 删除 _openAnyMd/_newDoc（-42 行）275→233；
        // #338 _Header 真正补回 Icons.search 按钮（+7 行）233→240。
        // 违规行为未变，仅位置维护。
        'lib/presentation/screens/home_screen.dart:240',
      ];
      final hits = <String>[];
      final dir = Directory('lib/presentation');
      if (!dir.existsSync()) {
        fail('lib/presentation 不存在');
      }
      for (final entity in dir.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final lines = entity.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          final trimmed = line.trim();
          if (trimmed.startsWith('//') || trimmed.startsWith('*')) continue;
          // 检测 doc.content / document.content 直读
          if (RegExp(r'\b(?:doc|document)\.content\b').hasMatch(line) &&
              !line.contains('getDocumentPreview')) {
            final key = '${entity.path.replaceAll("\\", "/")}:${i + 1}';
            if (knownOffenders.contains(key)) continue;
            hits.add('$key:${line.trim()}');
          }
        }
      }
      expect(
        hits,
        isEmpty,
        reason: 'ADR-0020 Decision 1：presentation/ 禁止直接读取 Document.content。\n'
            '命中：\n${hits.join("\n")}',
      );
    });
  });
}
