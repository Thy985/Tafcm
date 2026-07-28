import '../core/services/formula_svg_service.dart';

/// presentation 经此 providers 层访问 [FormulaSvgService]，
/// 避免 `lib/presentation/` 直接 import `core/services/`（TC-ARCH-3 分层守门）。
///
/// 与 mermaid 同源（`lib/presentation/blocks/mermaid/mermaid_block.dart` 经历史违例名单登记，
/// 待 Phase 3.9+ 统一改为 Riverpod Provider 注入）。当前为静态方法薄封装：
/// [FormulaBlock] 是纯 presentational `StatefulWidget`、无 `WidgetRef`，故以函数暴露，
/// 不引入 Riverpod 依赖链。providers 层允许 import core/services，故本文件合法。
Future<String> renderFormulaToSvg(String latex, {bool displayMode = false}) =>
    FormulaSvgService.renderToSvg(latex, displayMode: displayMode);

/// 同步读取公式 SVG 缓存（[FormulaSvgService.cachedSvg] 的 providers 层封装）。
String? formulaSvgCached(String latex, {bool displayMode = false}) =>
    FormulaSvgService.cachedSvg(latex, displayMode: displayMode);
