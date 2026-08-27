# Export Model（导出架构）

**定位（L2 架构真相）**：当前导出系统——只讲"现在是什么"，
"为什么这么设计"见 [ADR-0005](../decisions/ADR/0005-exporter-facade-dependency-injection.md)。

## 导出管线

```
Document AST
   ↓
Export IR（公式预渲染：SVG 优先 → PNG 回退 → 文本兜底）
   ↓
MarkdownExporter / WordExporter / PdfExporter / TextExporter（facade 静态）
   ↓
消费端（WPS / OfficeCLI / PDF 阅读器）
```

## 关键组件

| 组件 | 文件 | 职责 |
|------|------|------|
| `MarkdownExporter` | `lib/domain/services/export_service.dart` | facade + DI（register 注入 fake） |
| `PdfExporter` | `lib/domain/services/exporters/pdf_exporter.dart` | Markdown → PDF（SVG 矢量硬约束） |
| `WordExporter` | `lib/domain/services/exporters/word_exporter.dart` | Markdown → docx（OOXML） |
| `FormulaRenderPlan` | `lib/domain/services/exporters/formula_render_plan.dart` | SVG/PNG/文本三选一 + sanitizeSvgString |
| `SvgPdfWidget` | `lib/core/renderers/svg_to_pdf.dart` | SVG AST → PdfGraphics（绕开 pw.SvgImage utf8 bug） |

## 关键边界

- SVG 优先（矢量导出硬约束），失败回退 PNG，最终文本
- UTF8 边界：`sanitizeSvgString` 防御未配对 surrogate（DEBT-009 部分缓解）
- 静态状态：`PdfExporter.clearCjkFontCache()`（DEBT-016 已修）

## 消费端验证

- Word：Full Golden Loop（RUN-011）+ OOXML 语义保真
- PDF：Real Defect Repair Loop（RUN-007）+ DOCX-QA 管线
