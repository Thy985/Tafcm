# Tafcm Agent Finding Registry（机器维护，Agent 读取去重）

> 每行 = 一个稳定 Finding 身份（fingerprint）。Agent 运行前先读本表：
> fingerprint 命中 = 旧 Finding 的延续（标 UNCHANGED/UPDATED 并关联既有 Issue），
> 不得重新标 NEW / 不得新建 Issue。由 fingerprint.py 自动维护。

| fingerprint | latest_id | category | evidence | status | issue | first_seen | last_seen |
|-------------|-----------|----------|----------|--------|-------|------------|-----------|
| 6da41f553e19b36d | F-2026-09-01-06 | tech-debt | formula_extractor.dart | UNCHANGED | N/A | 2026-09-01 | 2026-09-01 |
| b7d1e0474dd11bfb | F-2026-09-01-05 | architecture | pdf_exporter.dart | UNCHANGED | N/A | 2026-09-01 | 2026-09-01 |
| ba2d023f01c1cb99 | F-2026-09-01-03 | test-gap | word_export_semantic_fidelity_test.dart | UNCHANGED | N/A | 2026-09-01 | 2026-09-01 |
| bbf9a480d573c2a9 | F-2026-09-01-07 | tech-debt | editor_export_actions.dart,export_progress_overlay.dart | RESOLVED | #215（应关闭） | 2026-09-01 | 2026-09-01 |
| f027bf84177c8c4a | F-2026-09-01-04 | regression |  | UNCHANGED | N/A | 2026-09-01 | 2026-09-01 |
| f11dda107944f8e3 | F-2026-09-01-02 | bug | formula_pdf_renderer.dart,word_exporter.dart | UNCHANGED | #216 | 2026-09-01 | 2026-09-01 |
| f75bceb75c53feba | F-2026-09-01-01 | bug | svg_to_pdf.dart,mermaid_renderer.html,svg_parser.dart | UNCHANGED | #216 | 2026-09-01 | 2026-09-01 |
<!-- REGISTRY_ROWS -->
