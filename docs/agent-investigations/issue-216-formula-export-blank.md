# Investigation: #216 —— 导出的公式渲染空白（PDF / Word）

> 深度调查文档（不属于 Audit 本体，也不塞进 Issue 正文）。Issue #216 只保留当前结论，细节在此。

## Question

为什么导出 PDF / Word 后，**任意**公式都渲染为空白 / 缺失（非 `[$...$]` 文本化、非乱码）？

## Evidence

- 用户确认（2026-08-31）：PDF 和 Word 都出现；任何公式都空白；排除 P0-D 密度降级（那只影响 ≥8 公式分片且表现为文本化）。
- `flutter_app/assets/mermaid_renderer.html:8`：`MathJax = { svg: { fontCache: 'global' } }` → 真实 tex-svg.js 输出为 `<defs>` 存字形 + `<use xlink:href>` 引用。
- `flutter_app/lib/core/renderers/svg_parser.dart`：`<defs>` 直接丢弃（`case 'defs': return null`），`<use>` 解析为 `SvgUse` 但不解析引用目标。
- `flutter_app/lib/core/renderers/svg_to_pdf.dart:246`：`SvgUse → _drawUnsupported` → 画 `[unsupported: <use href="...">]` 占位符（8pt 固定 (4,10)，超出 MathJax viewBox 小盒体 → 不可见）。
- `flutter_app/lib/core/services/formula_pdf_renderer.dart:209-242`：`_OffscreenCapture` 捕获体被 `Opacity(opacity: 0.0)` 包裹，`RepaintBoundary.toImage()` 合成 alpha=0 → 疑似全透明 PNG。
- `flutter_app/lib/domain/services/exporters/word_exporter.dart`：Word 公式 100% 走 `FormulaPdfRenderer`（PNG），无 SVG 路径。
- `flutter_app/lib/domain/services/exporters/pdf_exporter.dart:139-175`（buildFormulaPlan）：SVG 缓存 miss → PNG 缓存 → FormulaRenderHost 离屏 → fallback。
- 历史验证缺口：`docs/releases/phase3.5-realdevice-issues.md` E2E-P0-8 只验“PDF 公式导出不崩溃”；:371 明确“公式渲染质量由真机人工验收”。

## Root Cause

两个独立缺陷叠加，均以“空白”呈现：

1. **SVG 矢量路径无法渲染真实 MathJax 字形**（F-2026-09-01-01，High confidence）：`<use>` 引用未被解析 → 每个字形画成占位符 / 裁剪不可见。
2. **PNG fallback 路径疑似产出全透明图**（F-2026-09-01-02，Medium confidence，需真机 PoC）：`Opacity(0.0)` 捕获 → 透明 PNG → Word 恒中招；PDF 在 WebView 失败时也中招。

Word 端只有 PNG 路径（缺陷 2 足够解释 Word 空白）；PDF 端若 WebView 正常走 SVG 会命中缺陷 1（表现为乱占位），若 WebView 失败走 PNG 命中缺陷 2（表现为空白）。用户观察到“PDF 空白”说明其设备上 PDF 落到了 PNG 路径（WebView/SVG 预渲染失败）。

## Alternatives

- 修复 A（SVG 路径）：`parseSvgString` 阶段把 `<use href="#id">` 内联为 `<defs>` 中对应 `<path>`。成本低，保留矢量导出硬约束。
- 修复 B（PNG 路径）：把捕获体改为“不透明但不可见”的容器（`Offstage` + 固定尺寸 / `IgnorePointer` + 移出可视区），确保 `toImage` 捕获真实像素；并在捕获后断言 PNG 非全透明。
- 方案 C（统一渲染）：用 flutter_math_fork 统一三路渲染，去 WebView 依赖。成本高，见 E-2026-09-01-01，暂不采纳。

## Ecosystem Research

- 见 Audit E-2026-09-01-01/02/03。`pw.SvgImage` 不可替代（utf8 边界 bug）；WebView 底座 flutter_inappwebview 稳定版陈旧。

## Recommendation

1. 真机 PoC：导出 `$E=mc^2$` 最简文档（PDF+Word），logcat grep `FormulaQuality`/`FormulaTelemetry` 确认 PDF 走 SVG 还是 PNG；解包 Word `word/media/formula_1.png` 检查 alpha 通道是否全 0。
2. 按 Alternatives A + B 修复，修复后补回归（PNG alpha 非全透明 + 真实 `<use>` SVG 渲染）。

## Decision

待定（依赖 PoC 结果与维护者确认）。

## Follow-up

- [ ] 真机 PoC 采集 PNG alpha / 渲染路径日志
- [ ] 修复 F-01（SVG `<use>` 内联解析）
- [ ] 修复 F-02（捕获体不透明化）+ PNG 可见性断言
- [ ] 补 ADR-0032（P0-D 决策留档）
- [ ] 关闭 #215（修复已合入 PR #214）
