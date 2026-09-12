/// MathJax SVG 子集的 `<defs>`/`<use>` 解析适配器（#216 F-01 修复）。
///
/// 定位：**MathJax 输出适配器**，不是通用 SVG 解析器（Human Owner 决策，
/// 2026-09-12）。MathJax（v2/v3）的 glyph 机制高度规范：`<defs>` 内是
/// 具名 path（id 形如 `E1-MJMAIN-28`），`<use xlink:href="#E1-..." />`
/// 按坐标引用——本文件只覆盖这个子集，超出子集的元素忽略、整体失败时
/// 返回 null 交由 svg_parser 原路径（SvgUse → `_drawUnsupported`
/// fallback）。
///
/// MathJax 输出结构（实测 fixture）：
/// ```
/// <defs><path id="E1-MJMAIN-28" d="..." stroke-width="0" .../></defs>
/// <g data-mjx-...><use data-c="..." xlink:href="#E1-MJSZ2-2211" x="0" y="0"/></g>
/// ```
///
/// 坐标系：MathJax glyph 的 y 向下为正，根部 `<g transform="scale(1,-1)">`
/// 统一翻转——resolver 保留该变换为 [SvgScale]（svg_ast 节点），翻转
/// 语义由 svg_to_pdf 绘制层实现，本文件不做坐标系假设。
///
/// XML 解析用 `package:xml`（与 svg_parser.dart 同栈，零新依赖）。
library;

import 'package:xml/xml.dart';

import 'svg_ast.dart';

/// 递归深度上限（防损坏 SVG 的引用环）。
const int _kMaxNestDepth = 32;

/// `<defs>` 收集 + `<use>` 内联的结果。
class DefsResolution {
  const DefsResolution({required this.root});

  /// 内联后的根节点（无 `<defs>`、无 `<use>` 的纯绘制树）。
  final SvgRoot root;
}

/// 从 SVG XML 字符串解析并内联 defs/use。
///
/// 返回 null 表示无 defs/use（调用方走原解析路径，零开销）或解析失败。
DefsResolution? resolveSvgDefs(String svgXml) {
  if (!svgXml.contains('<defs') && !svgXml.contains('<use')) return null;
  final XmlDocument doc;
  try {
    doc = XmlDocument.parse(svgXml);
  } on XmlException {
    return null;
  }
  final XmlElement svgEl;
  try {
    svgEl = doc.rootElement;
  } on StateError {
    return null;
  }
  if (svgEl.name.local.toLowerCase() != 'svg') return null;

  final defs = <String, XmlElement>{};
  _collectDefs(svgEl, defs);
  if (defs.isEmpty) return null;

  final children = _resolveChildren(svgEl, defs, depth: 0);
  if (children.isEmpty) return null;

  final width = _parseDouble(svgEl.getAttribute('width'));
  final height = _parseDouble(svgEl.getAttribute('height'));
  var vbX = 0.0, vbY = 0.0, vbW = width ?? 0, vbH = height ?? 0;
  final viewBox = svgEl.getAttribute('viewBox');
  if (viewBox != null) {
    final parts = viewBox.split(RegExp(r'[ ,]+'));
    if (parts.length >= 4) {
      vbX = _parseDouble(parts[0]) ?? 0;
      vbY = _parseDouble(parts[1]) ?? 0;
      vbW = _parseDouble(parts[2]) ?? vbW;
      vbH = _parseDouble(parts[3]) ?? vbH;
    }
  }

  return DefsResolution(
    root: SvgRoot(
      children: children,
      viewBoxX: vbX,
      viewBoxY: vbY,
      viewBoxWidth: vbW,
      viewBoxHeight: vbH,
      width: width,
      height: height,
    ),
  );
}

/// 收集所有 `<defs>` 下的具名元素（MathJax glyph 只用 path，其余忽略）。
void _collectDefs(XmlElement el, Map<String, XmlElement> defs) {
  for (final d in el.findAllElements('defs')) {
    for (final child in d.childElements) {
      final id = child.getAttribute('id');
      if (id != null && id.isNotEmpty) {
        defs[id] = child;
      }
    }
  }
}

/// 递归解析 [el] 的子元素树为 AST 节点列表。
List<SvgNode> _resolveChildren(
  XmlElement el,
  Map<String, XmlElement> defs, {
  required int depth,
}) {
  if (depth > _kMaxNestDepth) return const [];
  final children = <SvgNode>[];
  for (final child in el.childElements) {
    final node = _resolveElement(child, defs, depth: depth + 1);
    if (node != null) children.add(node);
  }
  return children;
}

/// 单个 XML 元素 → AST 节点；`<use>` 查表内联。
SvgNode? _resolveElement(
  XmlElement el,
  Map<String, XmlElement> defs, {
  required int depth,
}) {
  if (depth > _kMaxNestDepth) return null; // 引用环守卫
  switch (el.name.local.toLowerCase()) {
    case 'g':
      return _resolveGroup(el, defs, depth: depth);
    case 'use':
      return _inlineUse(el, defs, depth: depth);
    case 'path':
      return _parsePathEl(el);
    case 'rect':
      return _parseRectEl(el);
    case 'line':
      return _parseLineEl(el);
    case 'circle':
      return _parseCircleEl(el);
    default:
      return null; // defs / 子集外元素 → 不绘制
  }
}

/// `<g>`：支持 translate 与 scale（MathJax 根部 `scale(1,-1)` 是 glyph
/// 正立的必需变换；translate+scale 并存时先平移再缩放）。
SvgNode? _resolveGroup(
  XmlElement el,
  Map<String, XmlElement> defs, {
  required int depth,
}) {
  final transform = el.getAttribute('transform') ?? '';
  final translate = RegExp(r'translate\(([-\d.eE]+)[, ]+([-\d.eE]+)\)')
      .firstMatch(transform);
  final scale = RegExp(r'scale\(([-\d.eE]+)(?:[, ]+([-\d.eE]+))?\)')
      .firstMatch(transform);

  final children = _resolveChildren(el, defs, depth: depth + 1);
  if (children.isEmpty) return null;
  final group = SvgGroup(
    children: children,
    translateX: _parseDouble(translate?.group(1)) ?? 0,
    translateY: _parseDouble(translate?.group(2)) ?? 0,
  );

  if (scale != null) {
    final sx = _parseDouble(scale.group(1)) ?? 1;
    final sy = _parseDouble(scale.group(2)) ?? sx;
    return SvgScale(scaleX: sx, scaleY: sy, child: group);
  }
  return group;
}

/// `<use>`：查 defs 表内联为具体形状节点（MathJax glyph 场景是 path）。
///
/// SVG 语义：`<use>` 处显式指定的 fill/stroke 覆盖被引用 path 的属性。
SvgNode? _inlineUse(
  XmlElement el,
  Map<String, XmlElement> defs, {
  required int depth,
}) {
  final href =
      el.getAttribute('xlink:href') ?? el.getAttribute('href');
  if (href == null || !href.startsWith('#')) return null;
  final target = defs[href.substring(1)];
  if (target == null) return null; // 未知引用 → 交 fallback
  final inlined = _resolveElement(target, defs, depth: depth + 1);
  if (inlined is! SvgPath) return inlined;

  final useFill = el.getAttribute('fill');
  final useStroke = el.getAttribute('stroke');
  if (useFill == null && useStroke == null) return inlined;
  return SvgPath(
    d: inlined.d,
    fill: useFill ?? inlined.fill,
    stroke: useStroke ?? inlined.stroke,
    strokeWidth: inlined.strokeWidth,
    fillOpacity: inlined.fillOpacity,
  );
}

SvgNode? _parsePathEl(XmlElement el) {
  final d = el.getAttribute('d');
  if (d == null || d.isEmpty) return null;
  return SvgPath(
    d: d,
    fill: el.getAttribute('fill'),
    stroke: el.getAttribute('stroke'),
    strokeWidth: _parseDouble(el.getAttribute('stroke-width')) ?? 1,
    fillOpacity: _parseDouble(el.getAttribute('fill-opacity')) ?? 1,
  );
}

SvgNode? _parseRectEl(XmlElement el) {
  final w = _parseDouble(el.getAttribute('width')) ?? 0;
  final h = _parseDouble(el.getAttribute('height')) ?? 0;
  if (w <= 0 || h <= 0) return null;
  return SvgRect(
    x: _parseDouble(el.getAttribute('x')) ?? 0,
    y: _parseDouble(el.getAttribute('y')) ?? 0,
    width: w,
    height: h,
    fill: el.getAttribute('fill'),
    stroke: el.getAttribute('stroke'),
    strokeWidth: _parseDouble(el.getAttribute('stroke-width')) ?? 1,
  );
}

SvgNode? _parseLineEl(XmlElement el) {
  return SvgLine(
    x1: _parseDouble(el.getAttribute('x1')) ?? 0,
    y1: _parseDouble(el.getAttribute('y1')) ?? 0,
    x2: _parseDouble(el.getAttribute('x2')) ?? 0,
    y2: _parseDouble(el.getAttribute('y2')) ?? 0,
    stroke: el.getAttribute('stroke'),
    strokeWidth: _parseDouble(el.getAttribute('stroke-width')) ?? 1,
  );
}

SvgNode? _parseCircleEl(XmlElement el) {
  final r = _parseDouble(el.getAttribute('r')) ?? 0;
  if (r <= 0) return null;
  return SvgCircle(
    cx: _parseDouble(el.getAttribute('cx')) ?? 0,
    cy: _parseDouble(el.getAttribute('cy')) ?? 0,
    r: r,
    fill: el.getAttribute('fill'),
    stroke: el.getAttribute('stroke'),
    strokeWidth: _parseDouble(el.getAttribute('stroke-width')) ?? 1,
  );
}

double? _parseDouble(String? raw) {
  if (raw == null) return null;
  return double.tryParse(raw.trim());
}
