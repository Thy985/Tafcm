/// EditorPage 文档加载辅助函数（P1 B-4 / P1 B-5 / #319）。
///
/// 从 editor_page.dart 抽取，保持单一职责（AGENTS.md §1.2）。
/// 提供文件加载失败的用户反馈、MarkdownParser 行级降级的 observability 上报、
/// 以及种子文档构造（EditorPage 行数控制，TC-ARCH-7）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/parser/markdown_parser.dart';
import '../../providers/editor_providers.dart';
import 'in_memory_document_editor.dart';
import 'seed_documents.dart';

/// 构造种子 [InMemoryDocumentEditor]（演示 / 加载失败回退路径）。
///
/// 自 EditorPage 抽取（#319 顺带，EditorPage 行数贴 400 上限）。
InMemoryDocumentEditor buildSeedEditor(int selector) {
  switch (selector) {
    case 0:
      return SeedDocuments.createDemo1();
    case 1:
      return SeedDocuments.createDemo2();
    case 2:
      return SeedDocuments.createDemo3();
    default:
      return SeedDocuments.createDemo1();
  }
}

/// P1 B-4：文件加载失败的 SnackBar 反馈。
///
/// 在 _ready=true 之后调用（_coordinator 已就绪，ScaffoldMessenger 可用）。
/// 用户提供路径与异常类型，但不展示 stack / detail（AGENTS.md §4.4）。
void showFileLoadFailureSnackBar(
  BuildContext context, {
  String? path,
  Object? error,
}) {
  if (!context.mounted) return;
  final where = path != null ? '文件 $path' : '所选文件';
  final reason = error == null
      ? '未知错误'
      : '${error.runtimeType}: ${error.toString().split('\n').first}';
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text('无法打开$where，已加载演示文档。\n原因：$reason'),
      duration: const Duration(seconds: 5),
      action: SnackBarAction(
        label: '知道了',
        onPressed: () {},
      ),
    ),
  );
}

/// P1 B-5：构造 MarkdownParser 的 onError 回调。
///
/// 把单行解析降级事件送入 observability（captureError），
/// 让用户 / 诊断 zip 能看到"哪些行解析失败、为什么失败"。
/// 不弹 UI——单行降级不打断用户阅读，仅在诊断数据中可见。
MarkdownParseErrorHandler buildParserErrorHandler(
  WidgetRef ref,
  String source,
) {
  return (lineIndex, error, line) {
    debugPrint('[EditorPage] parser line $lineIndex failed: $error');
    ref.read(observabilityProvider).captureError(
          type: 'MarkdownParseError',
          message: '$error',
          commandName: 'MarkdownParser.parse',
          commandParams: {
            'source': source,
            'lineIndex': lineIndex,
            'line': line.length > 200 ? '${line.substring(0, 200)}...' : line,
          },
        );
  };
}
