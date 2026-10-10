/// 文档动作：新建 / 导入外部 .md（首页与文件页共用，issue #338）。
///
/// 从 home_screen 抽出的共享导航动作：
/// - [newDoc]：新建库内文档并进入编辑器（可写，自动保存生效）。
/// - [openAnyMd]：导入外部 .md 文件（file_picker 选择，**只读查看**，issue
///   #330——file_picker 在 Android 返回的是应用私有缓存副本，写盘不会到达
///   用户原文件，必须按只读打开避免「可编辑但退出即丢」假象）。
library;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/file_repository_provider.dart';

/// 新建库内文档并进入编辑器。
Future<void> newDoc(WidgetRef ref, BuildContext context) async {
  final repo = ref.read(fileRepositoryProvider);
  final path = await repo.createDocument('未命名文档', '# 未命名文档\n\n');
  // P1 修复（2026-08-09）：go 替换路由，脱离 ShellRoute 消除底部导航栏。
  if (context.mounted) context.go('/editor?path=${Uri.encodeComponent(path)}');
}

/// 导入外部 .md 文件（只读查看）。
///
/// 选择器说明（P0 修复 2026-08-04 真机定位）：原用 FileType.custom +
/// allowedExtensions:['md']，file_picker 8.3.7 会把它转成
/// Intent(type='*/*', EXTRA_MIME_TYPES=['text/markdown'])。小米 HyperOS 的
/// SAF 实现对该配置过滤异常 → 弹窗完全空白。改用 FileType.any 让 SAF 显示
/// 所有文件，Dart 层校验 .md 扩展名：非 .md 时提示用户并中止。
/// #330：外部文件不可回写原文件，按只读查看打开（readOnly=1）。
Future<void> openAnyMd(BuildContext context) async {
  final result = await FilePicker.platform.pickFiles(type: FileType.any);
  final path = result?.files.single.path;
  if (path == null) return; // 用户取消
  if (!path.toLowerCase().endsWith('.md')) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('仅支持 .md 文件'),
          duration: Duration(seconds: 2),
        ),
      );
    }
    return;
  }
  if (context.mounted) {
    context.go('/editor?path=${Uri.encodeComponent(path)}&readOnly=1');
  }
}
