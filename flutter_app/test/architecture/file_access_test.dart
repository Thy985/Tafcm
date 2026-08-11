/// TC-ARCH-1 / TC-ARCH-2: 架构守门 - 文件系统访问唯一入口
///
/// 对应 ADR-0003、AGENTS.md §4.2 / §4.3。
library;

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TC-ARCH-1 业务层禁止直接访问文件系统', () {
    test('lib/presentation/ 不直接使用 File() / Directory()', () {
      // 已知历史违法（AGENTS.md §10 "DocumentListScreen 死代码"）：
      //   - file_manager_screen.dart:69 File().delete()
      // Phase 1 1.3 仅注册路由，未清理死代码；待 P2 完全清理。
      // 注：行号因前置 import 行插入而由 :68 顺移至 :69，属已知违例位置变更，非新增违例。
      const knownOffenders = <String>[
        'lib/presentation/screens/file_manager_screen.dart:69',
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
          if (RegExp(r'\bFile\s*\(').hasMatch(line) ||
              RegExp(r'\bDirectory\s*\(').hasMatch(line) ||
              RegExp(r'\bRandomAccessFile\b').hasMatch(line)) {
            final key = '${entity.path.replaceAll("\\", "/")}:${i + 1}';
            if (knownOffenders.contains(key)) continue;
            hits.add('$key:${line.trim()}');
          }
        }
      }
      expect(
        hits,
        isEmpty,
        reason: 'ADR-0003 要求文件操作必须经 data/storage/FileRepository。\n'
            '命中：\n${hits.join("\n")}',
      );
    });
  });

  group('TC-ARCH-2 Repository 唯一文件 I/O 入口', () {
    test('File.writeAsString / readAsString 仅出现在允许位置', () {
      // 允许位置（白名单）：
      //   - core/services/file_repository.dart   (Repository 本体)
      //   - core/services/file_service.dart       (decodeBytesAuto + 旧 FileService 兼容)
      //   - core/services/storage_migration.dart  (迁移)
      //   - core/services/document_service.dart   (历史遗留，AGENTS.md §10 "三套存储并存"，Phase 1 1.2 修复)
      //   - domain/services/export_service.dart   (临时导出文件写入，非用户文档)
      //   - core/services/asset_service.dart       (ADR-0014 资产 IO 唯一入口：
      //     图片复制到 documents/assets/，writeAsBytes 仅此一处；与
      //     FileRepository（文档 IO）平行，Phase 3.4 Slice 4 登记)
      //   - core/observability/export_pipeline.dart (Phase 3.7.3 诊断导出管道：
      //     生成 zip 到应用文档目录，非用户文档；file I/O 是导出功能的核心职责)
      final allowedRoots = [
        'lib/core/services/file_repository.dart',
        'lib/core/services/file_service.dart',
        'lib/core/services/storage_migration.dart',
        'lib/core/services/document_service.dart',
        'lib/domain/services/export_service.dart',
        'lib/core/services/asset_service.dart',
        'lib/core/observability/export_pipeline.dart',
        'lib/core/observability/adi_storage.dart',
      ];
      final hits = <String>[];
      final libDir = Directory('lib');
      for (final entity in libDir.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final path = entity.path.replaceAll('\\', '/');
        final isAllowed = allowedRoots.any((r) => path.endsWith(r));
        if (isAllowed) continue;
        final lines = entity.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          final trimmed = line.trim();
          if (trimmed.startsWith('//') || trimmed.startsWith('*')) continue;
          if (RegExp(r'\.writeAsString\s*\(').hasMatch(line) ||
              RegExp(r'\.readAsString\s*\(').hasMatch(line) ||
              RegExp(r'\.writeAsBytes\s*\(').hasMatch(line)) {
            hits.add('${entity.path}:${i + 1}:${line.trim()}');
          }
        }
      }
      expect(
        hits,
        isEmpty,
        reason: 'AGENTS.md §4.2 要求文件 I/O 经 FileRepository。\n'
            '命中：\n${hits.join("\n")}',
      );
    });
  });
}
