# Issue #216 深度调查：导出的公式渲染空白（PDF / Word）

> 调查日期：2026-09-01 · 关联 Audit：docs/agent-audit/2026-09-01-maintainer-audit.md
> 关联 Finding：F-2026-09-01-01（SVG `<use>` 字形无法渲染）、F-2026-09-01-02（离屏捕获疑似全透明 PNG）
> 说明：本调查由 Doubao Supervisor（监督层）在 Human Owner 授权下完成；Issue #216 只保留当前结论，调查全过程（证据链 / 排除假设 / 生态对比）在此归档。

## 1. 问题陈述

用户确认（2026-08-31）：导出 PDF / Word 后，**任意**公式都渲染为空白 / 缺失（非 `[$...$]` 文本化、非乱码）。
已排除 P0-D 密度降级（那只影响 ≥8 公式分片且表现为文本化）。触发场景：任何包含数学公式的文档导出。

## 2. 调查过程

### 2.1 渲染路径分析

- `flutter_app/assets/mermaid_renderer.html:8`：`MathJax = { svg: { fontCache: 'global' } }` → 真实 tex-svg.js 输出为 `<defs>` 存字形 + `<use xlink:href>` 引用。
- `flutter_app/lib/core/renderers/svg_parser.dart`：`<defs>` 直接丢弃（`case 'defs': return null`），`<use>` 解析为 `SvgUse` 但不解析引用目标。
- `flutter_app/lib/core/renderers/svg_to_pdf.dart:246`：`SvgUse → _drawUnsupported` → 画 `[unsupported: <use href="...">]` 占位符（8pt 固定 (4,10)，超出 MathJax viewBox 小盒体 → 不可见）。
- `flutter_app/lib/core/services/formula_pdf_renderer.dart:209-242`：`_OffscreenCapture` 捕获体被 `Opacity(opacity: 0.0)` 包裹，`RepaintBoundary.toImage()` 合成 alpha=0 → 疑似全透明 PNG。
- `flutter_app/lib/domain/services/exporters/word_exporter.dart`：Word 公式 100% 走 `FormulaPdfRenderer`（PNG），无 SVG 路径。
- `flutter_app/lib/domain/services/exporters/pdf_exporter.dart:139-175`（buildFormulaPlan）：SVG 缓存 miss → PNG 缓存 → FormulaRenderHost 离屏 → fallback。
- 历史验证缺口：`docs/releases/phase3.5-realdevice-issues.md` E2E-P0-8 只验"PDF 公式导出不崩溃"；:371 明确"公式渲染质量由真机人工验收"。

### 2.2 缺陷判定

两个独立缺陷叠加，均以"空白"呈现：

1. **SVG 矢量路径无法渲染真实 MathJax 字形**（F-2026-09-01-01，High confidence）：`<use>` 引用未被解析 → 每个字形画成占位符 / 裁剪不可见。
2. **PNG fallback 路径疑似产出全透明图**（F-2026-09-01-02，Medium confidence，需真机 PoC）：`Opacity(0.0)` 捕获 → 透明 PNG → Word 恒中招；PDF 在 WebView 失败时也中招。

Word 端只有 PNG 路径（缺陷 2 足够解释 Word 空白）；PDF 端若 WebView 正常走 SVG 会命中缺陷 1（表现为乱占位），若 WebView 失败走 PNG 命中缺陷 2（表现为空白）。用户观察到"PDF 空白"说明其设备上 PDF 落到了 PNG 路径（WebView/SVG 预渲染失败）。

## 3. 已排除的假设

- 假设 A（P0-D 密度降级）：排除——仅影响 ≥8 公式分片，且表现为文本化而非空白。
- 假设 B（MathJax 未加载）：排除——空白是"字形缺失"而非"整段公式缺失"，SVG 结构已生成。
- 假设 C（Word 编码问题）：排除——Word 公式全走 PNG 路径，与文本编码无关。

## 4. 根因结论

Root Cause: Likely

两个独立缺陷叠加（见 §2.2），各自在不同导出路径上以"空白"呈现。F-01 证据充分（代码路径明确），F-02 需真机 PoC 确认 alpha 通道。

## 5. 建议

1. 真机 PoC：导出 `$E=mc^2$` 最简文档（PDF+Word），logcat grep `FormulaQuality` / `FormulaTelemetry` 确认 PDF 走 SVG 还是 PNG；解包 Word `word/media/formula_1.png` 检查 alpha 通道是否全 0。
2. 按方案 A + B 修复后补回归：
   - 修复 A（SVG 路径）：`parseSvgString` 阶段把 `<use href="#id">` 内联为 `<defs>` 中对应 `<path>`。成本低，保留矢量导出硬约束。
   - 修复 B（PNG 路径）：把捕获体改为"不透明但不可见"的容器（`Offstage` + 固定尺寸 / `IgnorePointer` + 移出可视区），确保 `toImage` 捕获真实像素；并在捕获后断言 PNG 非全透明。
   - 回归测试：① PNG alpha 非全透明断言；② 真实 MathJax `<use>` SVG 渲染断言（补 F-2026-09-01-03 测试缺口）。

## 6. 参考

- Audit: docs/agent-audit/2026-09-01-maintainer-audit.md（F-2026-09-01-01/02/03）
- Issue: #216
- ADR: 无（注意：#216 正文引用的 ADR-0032 实际不存在，见 F-2026-09-01-05）
- Commit: PR #214 `92e6949`（#215 修复）
- Tests: `word_export_semantic_fidelity_test.dart:107-108`（测试环境无渲染器 → widthEmu=0 → 走 fallback）
- Ecosystem: Audit E-2026-09-01-01/02/03（`pw.SvgImage` 不可替代——utf8 边界 bug；WebView 底座 flutter_inappwebview 稳定版陈旧；统一渲染 flutter_math_fork 暂不采纳）
