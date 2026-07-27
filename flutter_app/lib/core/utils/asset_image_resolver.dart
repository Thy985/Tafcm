/// 本地图片资产路径解析（ADR-0014）。
///
/// presentation 层渲染 `ImageElement` 时统一经本工具把 Markdown 相对路径
/// （`assets/img_<hash>.<ext>`）解析为本地文件，避免各渲染器重复实现且
/// 直接触碰 `dart:io`（TC-ARCH-1 架构守门：presentation 不直接 `File()`）。
library;

import 'dart:io';

import 'package:path/path.dart' as p;

/// 把 Markdown 图片 url 解析为可渲染的本地文件。
///
/// 返回 `null` 表示应回退占位渲染，场景：
/// - [baseDir] 为空（文档基目录尚未解析完成）
/// - 网络地址（`http/https`，网络图渲染留 Phase 3.5）
/// - `data:` URI
/// - 解析后的文件不存在
///
/// TODO(Phase 3.5): `existsSync` 为同步 IO（单次 <1ms，SSD），列表快速滚动
/// 时可能高频触发；后续改 FutureBuilder / 预检查缓存（评审 2026-07-26 记录）。
File? resolveLocalImageFile(String? baseDir, String url) {
  if (baseDir == null || url.startsWith('http') || url.startsWith('data:')) {
    return null;
  }
  final file = File(p.join(baseDir, url));
  if (!file.existsSync()) return null;
  return file;
}
