# Changelog

> 正式版本历史（用户视角：发生了什么）。详细发布证据、验证记录见 [docs/releases/](docs/releases/)（工程师视角：这次发布是怎么证明的）。

## [0.1.0] - 2026-08-30（首个正式发布，tag v0.1.0）

首个可运行版本，Phase 0-3.11 完成。核心能力：

- **品牌改名** FormulaFix → **Tafcm**（L0+L1 代码层 + L2 叙事 + 工程资产整理）
- **自动代码审查**：claude-review 退役 → Cline（AGNES OpenAI-compatible 网关）+ Copilot review
- **知识体系三层化**：新增 `docs/principles/` + Engineering Handbook 入口

- **块级 WYSIWYG 编辑**：8 种 BlockType + Transaction 模型 + Undo/Redo
- **公式渲染**：LaTeX → SVG 矢量 + PNG 回退（真机验证）
- **Mermaid 图表**：WebView 渲染 → SVG 嵌入导出
- **导出**：Markdown / Word / PDF / 文本（SVG 矢量硬约束）
- **主题**：Light / Dark / Sepia（Design System Token 驱动）
- **便携查看器**：任意来源 .md 即开即看（ACTION_VIEW 注册）
- **可观测 / ADI**：渲染追踪 + Agent Diagnostic Interface

> 版本号沿用 `pubspec.yaml`（0.1.0+1）；正式发布前将接入动态版本读取。

<!--
维护规则：每个正式版本在此追加条目（Keep a Changelog 风格）；
详细证据不在此重复，指向 docs/releases/ 对应报告。
-->
