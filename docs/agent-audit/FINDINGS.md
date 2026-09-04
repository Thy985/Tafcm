# Tafcm Agent Finding Registry（机器维护，Agent 读取去重）

> 每行 = 一个稳定 Finding 身份（fingerprint）。Agent 运行前先读本表：
> fingerprint 命中 = 旧 Finding 的延续（标 UNCHANGED/UPDATED 并关联既有 Issue），
> 不得重新标 NEW / 不得新建 Issue。由 fingerprint.py 自动维护。

| fingerprint | latest_id | category | evidence | status | issue | first_seen | last_seen |
|-------------|-----------|----------|----------|--------|-------|------------|-----------|
| 14138cdee2a377b7 | F-2026-09-01-03 | test-gap | word_export_semantic_fidelity_test.dart | UNCHANGED | #234 | 2026-09-02 | 2026-09-02 |
| 2287adae59a02905 | F-2026-09-02-01 | regression |  | RESOLVED | #233 | 2026-09-02 | 2026-09-03 |
| 39c85d0b899f396b | F-2026-09-01-06 | architecture |  | RESOLVED | #215（已关闭） | 2026-09-02 | 2026-09-02 |
| 3bac87ff07c79bd3 | F-2026-09-01-04 | regression |  | RESOLVED | #233 | 2026-09-02 | 2026-09-03 |
| 3c473b74863e3a3f | F-2026-09-01-01 | bug | svg_to_pdf.dart,mermaid_renderer.html,issue-216-formula-export-blank.md | UNCHANGED | #216 | 2026-09-02 | 2026-09-02 |
| da5fbded93636dd2 | F-2026-09-01-05 | architecture |  | UNCHANGED | N/A | 2026-09-02 | 2026-09-02 |
| e853e8f6a7cddfba | F-2026-09-02-02 | tech-debt | report.json,generate_report.py | WATCH | N/A | 2026-09-02 | 2026-09-02 |
| f5469b957182e6c2 | F-2026-09-01-02 | bug | formula_pdf_renderer.dart,word_exporter.dart | UNCHANGED | #216 | 2026-09-02 | 2026-09-02 |
| a9f3c7d1e5b82044 | F-2026-09-05-01 | ci-infra | CI #840 android-emulator success, PR #254/#255/#256 | NEW | N/A | 2026-09-05 | 2026-09-05 |
| b2e8f4a6c9d13055 | F-2026-09-05-02 | ci-infra | tools/adi/test/import_zip_test.dart analyze errors | NEW | N/A | 2026-09-05 | 2026-09-05 |
| 14138cdee2a377b7 | F-2026-09-01-03 | test-gap | word_export_semantic_fidelity_test.dart | UNCHANGED | #234 | 2026-09-02 | 2026-09-02 |
| 2287adae59a02905 | F-2026-09-02-01 | regression |  | RESOLVED | #233 | 2026-09-02 | 2026-09-03 |
| 39c85d0b899f396b | F-2026-09-01-06 | architecture |  | RESOLVED | #215（已关闭） | 2026-09-02 | 2026-09-02 |
| 3bac87ff07c79bd3 | F-2026-09-01-04 | regression |  | RESOLVED | #233 | 2026-09-02 | 2026-09-03 |
| 3c473b74863e3a3f | F-2026-09-01-01 | bug | svg_to_pdf.dart,mermaid_renderer.html,issue-216-formula-export-blank.md | UNCHANGED | #216 | 2026-09-02 | 2026-09-02 |
| 758564f6e3c1ffb0 | F-2026-09-05-02 | tech-debt | import_zip_test.dart | NEW | N/A | 2026-09-05 | 2026-09-05 |
| a9f3c7d1e5b82044 | F-2026-09-05-01 | ci-infra | CI #840 android-emulator success, PR #254/#255/#256 | NEW | N/A | 2026-09-05 | 2026-09-05 |
| b04ac16ee32912cf | F-2026-09-05-01 | architecture | smoke_test.dart,phase35_home_smoke_test.dart | NEW | N/A | 2026-09-05 | 2026-09-05 |
| b2e8f4a6c9d13055 | F-2026-09-05-02 | ci-infra | tools/adi/test/import_zip_test.dart analyze errors | NEW | N/A | 2026-09-05 | 2026-09-05 |
| da5fbded93636dd2 | F-2026-09-01-05 | architecture |  | UNCHANGED | N/A | 2026-09-02 | 2026-09-02 |
| e853e8f6a7cddfba | F-2026-09-02-02 | tech-debt | report.json,generate_report.py | WATCH | N/A | 2026-09-02 | 2026-09-02 |
| f5469b957182e6c2 | F-2026-09-01-02 | bug | formula_pdf_renderer.dart,word_exporter.dart | UNCHANGED | #216 | 2026-09-02 | 2026-09-02 |
<!-- REGISTRY_ROWS -->
