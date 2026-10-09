/// 文档列表副标题（issue #333-C 同名消歧）。
///
/// QA 实测：两个文档可同名同预览，文件页两条同名「未命名文档」副标题重复
/// 标题原文，用户无法辨别目标（本轮即因误删一个条目）。
///
/// 策略：**仅在同名碰撞时**给副标题加创建时间前缀——种子文档标题不重复，
/// 故 HomeScreen / FileManager 的 golden 基线不受影响（碰撞才出现差异行）。
/// 纯函数，无 Riverpod / IO 依赖，便于单测。
library;

import '../../data/models/document.dart';

/// [docs] 中除 [doc] 自身外，是否有与 [doc] 同标题的其它文档。
bool hasTitleCollision(Document doc, List<Document> docs) =>
    docs.any((d) => !identical(d, doc) && d.title == doc.title);

/// 创建时间格式 `yyyy-MM-dd HH:mm`（不引入 intl 依赖）。
String formatDateTimeShort(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} '
      '${two(t.hour)}:${two(t.minute)}';
}

/// 同名碰撞时在 [snippet] 前加创建时间前缀；无碰撞原样返回。
///
/// 加前缀而非新增一行，避免改动 tile 纵向布局（保持 golden 像素一致）。
String disambiguatedSubtitle(
  Document doc,
  List<Document> docs,
  String snippet,
) {
  if (!hasTitleCollision(doc, docs)) return snippet;
  return '${formatDateTimeShort(doc.createdAt)} · $snippet';
}
