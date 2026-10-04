/// 解析 / 生成 .md 文档的 YAML front matter（最小集：id / createdAt / updatedAt）。
///
/// 设计要点（见 ADR-0003 §边界约束 3）：
/// `title` **不**写入 front matter，而由正文首个 `# H1` 推导，
/// 避免 front matter 与正文标题漂移。
library;

/// 首行 `---` 的解析结论（issue #318：解析不确定时禁止破坏性覆写）。
enum FrontMatterStatus {
  /// 首行不是 `---`：整份文本都是正文，无 front matter。
  noFrontMatter,

  /// 首行 `---` 且找到闭合标记：块内 `key: value` 为可信 meta。
  valid,

  /// 首行 `---` 但**无**闭合标记（`---` 只是合法的水平线），或闭合块内
  /// 没有一行 `key: value`（首行水平线 + 正文里另有 `---` 的误判）。
  /// 此时整份原文按正文处理，meta 不可信——宁可多显示几行也不吞正文。
  malformed,
}

/// [FrontMatterParser.parse] 的结果。
///
/// 不变量：`meta` 非 null **仅当** [status] 为 [FrontMatterStatus.valid]，
/// 调用方可无条件信任 `body` 为「文档应展示的正文」——解析不确定时
/// `body` 即整份原文（issue #318 数据丢失修复的核心契约）。
class FrontMatterParseResult {
  final FrontMatterStatus status;
  final Map<String, String>? meta;
  final String body;

  /// 被解析的原文（未经任何裁剪），供写端在不确定时原样回写。
  final String raw;

  const FrontMatterParseResult({
    required this.status,
    required this.meta,
    required this.body,
    required this.raw,
  });

  /// 解析结论是否可信（仅 [FrontMatterStatus.valid] 为 true）。
  /// 持久层据此决定能否采信 front matter 元数据。
  bool get isValid => status == FrontMatterStatus.valid;
}

class FrontMatterParser {
  static const String _sep = '---';

  /// 解析开头的 `--- ... ---` 块。
  ///
  /// - [FrontMatterStatus.noFrontMatter]：首行非 `---`，[body] 为全文。
  /// - [FrontMatterStatus.valid]：有闭合标记，[meta] 为 `key: value` 映射。
  /// - [FrontMatterStatus.malformed]：首行 `---` 但未闭合（或块内无任何
  ///   `key: value`）——`---` 更可能是 Markdown 水平线而非 front matter，
  ///   此时 [meta] 为 null 且 [body] == [raw] == 整份原文，**一行不丢**。
  ///
  /// 修复 issue #318：旧实现扫到文件尾仍未闭合时把全部正文当 meta 消费，
  /// 返回 `body = ''`，编辑器的任意一次自动保存即把文件覆写成空正文。
  static FrontMatterParseResult parse(String markdown) {
    final lines = markdown.split('\n');
    if (lines.isEmpty || lines[0].trim() != _sep) {
      return FrontMatterParseResult(
        status: FrontMatterStatus.noFrontMatter,
        meta: null,
        body: markdown,
        raw: markdown,
      );
    }
    final end = _closingIndex(lines);
    if (end < 0 || !_hasMetaLine(lines, end)) {
      return FrontMatterParseResult(
        status: FrontMatterStatus.malformed,
        meta: null,
        body: markdown,
        raw: markdown,
      );
    }
    final meta = <String, String>{};
    for (var i = 1; i < end - 1; i++) {
      final idx = lines[i].indexOf(':');
      if (idx > 0) {
        final k = lines[i].substring(0, idx).trim();
        final v = lines[i].substring(idx + 1).trim();
        if (k.isNotEmpty) meta[k] = v;
      }
    }
    final body = end < lines.length ? lines.sublist(end).join('\n') : '';
    return FrontMatterParseResult(
      status: FrontMatterStatus.valid,
      meta: meta,
      body: body,
      raw: markdown,
    );
  }

  /// 提取 [text] 中**已闭合**的 front matter 块（含首尾 `---` 行）；
  /// 首行非 `---` 或未闭合返回 null。
  ///
  /// 供读端在字节层面（尚未确定编码时，用 latin1 1:1 映射保结构）限定
  /// `encoding:` 声明的搜索范围——正文里出现 `encoding: gbk` 这类行时
  /// 不得被当成编码声明（issue #318 近邻缺陷）。
  static String? closedBlockOf(String text) {
    final lines = text.split('\n');
    if (lines.isEmpty || lines[0].trim() != _sep) return null;
    final end = _closingIndex(lines);
    if (end < 0) return null;
    return lines.sublist(0, end).join('\n');
  }

  /// 闭合标记所在行的下一行下标；无闭合返回 -1。[lines[0]] 须已是 `---`。
  static int _closingIndex(List<String> lines) {
    for (var i = 1; i < lines.length; i++) {
      if (lines[i].trim() == _sep) return i + 1;
    }
    return -1;
  }

  /// 闭合块内是否至少有一行 `key: value`（或只有空行）。
  ///
  /// 首行 `---` 若是水平线，正文中任意一条水平线都会被 `_closingIndex`
  /// 当成闭合标记，导致前面的正文被吞。此处要求块内确有 meta 形态的行，
  /// 否则整份按正文处理；嵌套结构（`- item` / 缩进行）不影响判定——
  /// 只要存在任一 `key: value` 即可。
  static bool _hasMetaLine(List<String> lines, int end) {
    var hasNonBlank = false;
    for (var i = 1; i < end - 1; i++) {
      final line = lines[i];
      if (line.trim().isEmpty) continue;
      hasNonBlank = true;
      if (line.indexOf(':') > 0) return true;
    }
    return !hasNonBlank;
  }

  /// 生成带 front matter 的 .md 文本。
  ///
  /// [title] 非空且正文本身没有前导 `# H1` 时，注入首个 `# H1`
  /// （避免与正文已有标题重复）。
  ///
  /// [encoding]（P0-2 §4.2）：非 null 时写入 `encoding: <name>` 声明，
  /// 读端据此选择解码器、写端据此编码写回（最小侵入的兼容方案，
  /// 默认仍 UTF-8 不写声明——ADR-0003 目标态不变）。
  static String build({
    required String id,
    required DateTime createdAt,
    required DateTime updatedAt,
    required String title,
    required String content,
    String? encoding,
  }) {
    final sb = StringBuffer();
    sb.writeln('---');
    sb.writeln('id: $id');
    sb.writeln('createdAt: ${createdAt.toIso8601String()}');
    sb.writeln('updatedAt: ${updatedAt.toIso8601String()}');
    if (encoding != null) sb.writeln('encoding: $encoding');
    sb.writeln('---');
    final trimmed = content.replaceFirst(RegExp(r'^\s+'), '');
    final hasLeadingH1 = trimmed.startsWith('# ');
    if (title.isNotEmpty && !hasLeadingH1) {
      sb.writeln('# $title');
      if (content.trim().isNotEmpty) sb.writeln();
    }
    sb.write(content);
    return sb.toString();
  }
}
