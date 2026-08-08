/// EditorPage 文档加载辅助函数（P1 B-4 / P1 B-5）。
///
/// 从 editor_page.dart 抽取，保持单一职责（AGENTS.md §1.2）。
/// 提供文件加载失败的用户反馈与 MarkdownParser 行级降级的 observability 上报。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';


import '../../core/parser/markdown_parser.dart';
import '../../providers/editor_providers.dart';

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