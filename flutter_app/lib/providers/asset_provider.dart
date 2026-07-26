/// 文档资源路径 Provider（ADR-0014 渲染层依赖）。
///
/// 渲染层（ParagraphRenderer / ListRenderer / ParagraphBlock）需要把 Markdown 中的
/// 相对资源路径（`assets/img_xxx.png`）解析为绝对路径。基目录即文档存储目录
/// `getApplicationDocumentsDirectory()/documents`，由本 Provider 解析后向下传递，
/// 避免渲染 Widget 直接依赖 IO（保持 chrome / widgets 层 Riverpod-free 的既有约定
/// 由持有 ref 的页面层解析后透传）。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/services/asset_service.dart';

/// 文档存储基目录（用于解析相对资源路径，如 `assets/img_xxx.png`）。
///
/// 值为 `<appDocsDir>/documents`；首次解析后由 [AssetService] 内部缓存。
final docsDirProvider = FutureProvider<String>((ref) async {
  return AssetService.documentsDir();
});

/// 图片「选择 + 导入 assets/」函数（ADR-0014）。
///
/// 页面层（EditorPage）解析后注入 MarkdownToolbar 的 `pickImage`，
/// chrome 层不直接 import core/services（TC-ARCH-3 分层守门）。
final imagePickAndImportProvider =
    Provider<Future<String?> Function()>((ref) {
  return AssetService.pickAndImportImage;
});
