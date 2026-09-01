# Tafcm Agent Finding Registry（机器维护，Agent 读取去重）

> 每行 = 一个稳定 Finding 身份（fingerprint）。Agent 运行前先读本表：
> fingerprint 命中 = 旧 Finding 的延续（标 UNCHANGED/UPDATED 并关联既有 Issue），
> 不得重新标 NEW / 不得新建 Issue。由 fingerprint.py 自动维护。

| fingerprint | latest_id | category | evidence | status | issue | first_seen | last_seen |
|-------------|-----------|----------|----------|--------|-------|------------|-----------|
| 2f97f4f95055bb1b | F-2026-09-01-02 | bug | svg_to_pdf.dart,mermaid_renderer.html,svg_parser.dart | UNCHANGED | #216 | 2026-09-01 | 2026-09-01 |
| 5172cb3b3d73cc07 | F-2026-09-01-01 | bug | formula_extractor.dart | NEW | N/A（实验注入，不建 Issue） | 2026-09-01 | 2026-09-01 |
| 5332015cd260a182 | F-2026-09-01-06 | architecture | pdf_exporter.dart | UNCHANGED | N/A（文档缺失，建议随 #216 修复一并处理） | 2026-09-01 | 2026-09-01 |
| 77d8078f85365146 | F-2026-09-01-04 | test-gap | word_export_semantic_fidelity_test.dart | UNCHANGED | N/A（测试缺口，随 #216 修复一并补） | 2026-09-01 | 2026-09-01 |
| 823f770dff1cc059 | F-2026-09-01-07 | tech-debt | editor_export_actions.dart,export_progress_overlay.dart | RESOLVED | #215（已关闭） | 2026-09-01 | 2026-09-01 |
| 9a386aafbaf01534 | F-2026-09-01-05 | regression |  | UNCHANGED | N/A（CI 配置问题，不建 Issue） | 2026-09-01 | 2026-09-01 |
| f2b6c6b7008959b4 | F-2026-09-01-03 | architecture | formula_pdf_renderer.dart,word_exporter.dart | UNCHANGED | #216 | 2026-09-01 | 2026-09-01 |
| 2f97f4f95055bb1b | F-2026-09-01-02 | bug | svg_to_pdf.dart,mermaid_renderer.html,svg_parser.dart | UNCHANGED | #216 | 2026-09-01 | 2026-09-01 |
| 5172cb3b3d73cc07 | F-2026-09-01-01 | bug | formula_extractor.dart | NEW | N/A（实验注入，不建 Issue） | 2026-09-01 | 2026-09-01 |
| 5332015cd260a182 | F-2026-09-01-06 | architecture | pdf_exporter.dart | UNCHANGED | N/A（文档缺失，建议随 #216 修复一并处理） | 2026-09-01 | 2026-09-01 |
| 77d8078f85365146 | F-2026-09-01-04 | test-gap | word_export_semantic_fidelity_test.dart | UNCHANGED | N/A（测试缺口，随 #216 修复一并补） | 2026-09-01 | 2026-09-01 |
| 823f770dff1cc059 | F-2026-09-01-07 | tech-debt | editor_export_actions.dart,export_progress_overlay.dart | RESOLVED | #215（已关闭） | 2026-09-01 | 2026-09-01 |
| 9a386aafbaf01534 | F-2026-09-01-05 | regression |  | UNCHANGED | N/A（CI 配置问题，不建 Issue） | 2026-09-01 | 2026-09-01 |
| f2b6c6b7008959b4 | F-2026-09-01-03 | architecture | formula_pdf_renderer.dart,word_exporter.dart | UNCHANGED | #216 | 2026-09-01 | 2026-09-01 |
<!-- REGISTRY_ROWS -->
