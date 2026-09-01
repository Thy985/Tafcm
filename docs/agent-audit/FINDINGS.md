# Tafcm Agent Finding Registry（机器维护，Agent 读取去重）

> 每行 = 一个稳定 Finding 身份（fingerprint）。Agent 运行前先读本表：
> fingerprint 命中 = 旧 Finding 的延续（标 UNCHANGED/UPDATED 并关联既有 Issue），
> 不得重新标 NEW / 不得新建 Issue。由 fingerprint.py 自动维护。

| fingerprint | latest_id | category | evidence | status | issue | first_seen | last_seen |
|-------------|-----------|----------|----------|--------|-------|------------|-----------|
| 04767cb19a5c087f | F-2026-09-01-04 | architecture | formula_density_degrade_test.dart,pdf_exporter.dart | UNCHANGED | N/A（文档缺失，不建 Issue） | 2026-09-01 | 2026-09-01 |
| 09205ad314b3b176 | F-2026-09-01-07 | bug | formula_extractor.dart | NEW | N/A（实验分支注入，暂不跨分支建 Issue；合并前必须修复） | 2026-09-01 | 2026-09-01 |
| 3fac76c7deb822fe | F-2026-09-01-08 | tech-debt | adi.dart,import_zip.dart,causality_test.dart | NEW | N/A | 2026-09-01 | 2026-09-01 |
| 4a3181d823ca3c40 | F-2026-09-01-06 | architecture | editor_export_actions.dart,export_progress_overlay.dart | UNCHANGED | #215（应关闭） | 2026-09-01 | 2026-09-01 |
| 77d8078f85365146 | F-2026-09-01-03 | test-gap | word_export_semantic_fidelity_test.dart | UNCHANGED | N/A（测试缺口，不建 Issue） | 2026-09-01 | 2026-09-01 |
| 934c2d8da35f915d | F-2026-09-01-05 | regression |  | UNCHANGED | N/A | 2026-09-01 | 2026-09-01 |
| a0f1f39cb5d3b28f | F-2026-09-01-02 | bug | formula_pdf_renderer.dart | UNCHANGED | #216 | 2026-09-01 | 2026-09-01 |
| b27dc61a34de0b2a | F-2026-09-01-01 | bug | svg_to_pdf.dart,svg_parser.dart | UNCHANGED | #216 | 2026-09-01 | 2026-09-01 |
| 04767cb19a5c087f | F-2026-09-01-04 | architecture | formula_density_degrade_test.dart,pdf_exporter.dart | UNCHANGED | N/A（文档缺失，不建 Issue） | 2026-09-01 | 2026-09-01 |
| 09205ad314b3b176 | F-2026-09-01-07 | bug | formula_extractor.dart | NEW | N/A（实验分支注入，暂不跨分支建 Issue；合并前必须修复） | 2026-09-01 | 2026-09-01 |
| 3fac76c7deb822fe | F-2026-09-01-08 | tech-debt | adi.dart,import_zip.dart,causality_test.dart | NEW | N/A | 2026-09-01 | 2026-09-01 |
| 4a3181d823ca3c40 | F-2026-09-01-06 | architecture | editor_export_actions.dart,export_progress_overlay.dart | UNCHANGED | #215（应关闭） | 2026-09-01 | 2026-09-01 |
| 77d8078f85365146 | F-2026-09-01-03 | test-gap | word_export_semantic_fidelity_test.dart | UNCHANGED | N/A（测试缺口，不建 Issue） | 2026-09-01 | 2026-09-01 |
| 934c2d8da35f915d | F-2026-09-01-05 | regression |  | UNCHANGED | N/A | 2026-09-01 | 2026-09-01 |
| a0f1f39cb5d3b28f | F-2026-09-01-02 | bug | formula_pdf_renderer.dart | UNCHANGED | #216 | 2026-09-01 | 2026-09-01 |
| b27dc61a34de0b2a | F-2026-09-01-01 | bug | svg_to_pdf.dart,svg_parser.dart | UNCHANGED | #216 | 2026-09-01 | 2026-09-01 |
<!-- REGISTRY_ROWS -->
