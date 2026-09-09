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
| 14138cdee2a377b7 | F-2026-09-01-03 | test-gap | word_export_semantic_fidelity_test.dart | UNCHANGED | #234 | 2026-09-02 | 2026-09-02 |
| 2287adae59a02905 | F-2026-09-02-01 | regression |  | RESOLVED | #233 | 2026-09-02 | 2026-09-03 |
| 39c85d0b899f396b | F-2026-09-01-06 | architecture |  | RESOLVED | #215（已关闭） | 2026-09-02 | 2026-09-02 |
| 3bac87ff07c79bd3 | F-2026-09-01-04 | regression |  | RESOLVED | #233 | 2026-09-02 | 2026-09-03 |
| 3c473b74863e3a3f | F-2026-09-01-01 | bug | svg_to_pdf.dart,mermaid_renderer.html,issue-216-formula-export-blank.md | UNCHANGED | #216 | 2026-09-02 | 2026-09-02 |
| 758564f6e3c1ffb0 | F-2026-09-05-02 | tech-debt | import_zip_test.dart | NEW | N/A | 2026-09-05 | 2026-09-05 |
| a9f3c7d1e5b82044 | F-2026-09-05-01 | ci-infra | CI #840 android-emulator success, PR #254/#255/#256 | NEW | N/A | 2026-09-05 | 2026-09-05 |
| b04ac16ee32912cf | F-2026-09-05-01 | architecture | smoke_test.dart,phase35_home_smoke_test.dart | NEW | N/A | 2026-09-05 | 2026-09-05 |
| b2e8f4a6c9d13055 | F-2026-09-05-02 | ci-infra | tools/adi/test/import_zip_test.dart analyze errors | NEW | N/A | 2026-09-05 | 2026-09-05 |
| b86e4b47a1b958e1 | F-2026-09-07-01 | ci-infra |  | NEW | #263（新建） | 2026-09-07 | 2026-09-07 |
| da5fbded93636dd2 | F-2026-09-01-05 | architecture |  | UNCHANGED | N/A | 2026-09-02 | 2026-09-02 |
| e853e8f6a7cddfba | F-2026-09-02-02 | tech-debt | report.json,generate_report.py | WATCH | N/A | 2026-09-02 | 2026-09-02 |
| f5469b957182e6c2 | F-2026-09-01-02 | bug | formula_pdf_renderer.dart,word_exporter.dart | UNCHANGED | #216 | 2026-09-02 | 2026-09-02 |
| f5da01a687870462 | F-2026-09-07-02 | architecture | 0032-audit-frontier-incremental.md | RESOLVED | N/A（架构决策文件，无需 Issue） | 2026-09-07 | 2026-09-07 |
| 14138cdee2a377b7 | F-2026-09-01-03 | test-gap | word_export_semantic_fidelity_test.dart | UNCHANGED | #234 | 2026-09-02 | 2026-09-02 |
| 2287adae59a02905 | F-2026-09-02-01 | regression |  | RESOLVED | #233 | 2026-09-02 | 2026-09-03 |
| 39c85d0b899f396b | F-2026-09-01-06 | architecture |  | RESOLVED | #215（已关闭） | 2026-09-02 | 2026-09-02 |
| 3bac87ff07c79bd3 | F-2026-09-01-04 | regression |  | RESOLVED | #233 | 2026-09-02 | 2026-09-03 |
| 3c473b74863e3a3f | F-2026-09-01-01 | bug | svg_to_pdf.dart,mermaid_renderer.html,issue-216-formula-export-blank.md | UNCHANGED | #216 | 2026-09-02 | 2026-09-02 |
| 758564f6e3c1ffb0 | F-2026-09-05-02 | tech-debt | import_zip_test.dart | NEW | N/A | 2026-09-05 | 2026-09-05 |
| a9f3c7d1e5b82044 | F-2026-09-05-01 | ci-infra | CI #840 android-emulator success, PR #254/#255/#256 | NEW | N/A | 2026-09-05 | 2026-09-05 |
| b04ac16ee32912cf | F-2026-09-05-01 | architecture | smoke_test.dart,phase35_home_smoke_test.dart | NEW | N/A | 2026-09-05 | 2026-09-05 |
| b2e8f4a6c9d13055 | F-2026-09-05-02 | ci-infra | tools/adi/test/import_zip_test.dart analyze errors | NEW | N/A | 2026-09-05 | 2026-09-05 |
| b86e4b47a1b958e1 | F-2026-09-07-01 | ci-infra |  | NEW | #263（新建） | 2026-09-07 | 2026-09-07 |
| da5fbded93636dd2 | F-2026-09-01-05 | architecture |  | UNCHANGED | N/A | 2026-09-02 | 2026-09-02 |
| e0d98ab667623d47 | F-2026-09-07-01 | tech-debt |  | NEW | #263 | 2026-09-07 | 2026-09-07 |
| e853e8f6a7cddfba | F-2026-09-02-02 | tech-debt | report.json,generate_report.py | WATCH | N/A | 2026-09-02 | 2026-09-02 |
| f5469b957182e6c2 | F-2026-09-01-02 | bug | formula_pdf_renderer.dart,word_exporter.dart | UNCHANGED | #216 | 2026-09-02 | 2026-09-02 |
| f5da01a687870462 | F-2026-09-07-02 | architecture | 0032-audit-frontier-incremental.md | RESOLVED | N/A | 2026-09-07 | 2026-09-07 |
| 14138cdee2a377b7 | F-2026-09-01-03 | test-gap | word_export_semantic_fidelity_test.dart | UNCHANGED | #234 | 2026-09-02 | 2026-09-02 |
| 2287adae59a02905 | F-2026-09-02-01 | regression |  | RESOLVED | #233 | 2026-09-02 | 2026-09-03 |
| 39c85d0b899f396b | F-2026-09-01-06 | architecture |  | RESOLVED | #215（已关闭） | 2026-09-02 | 2026-09-02 |
| 3bac87ff07c79bd3 | F-2026-09-01-04 | regression |  | RESOLVED | #233 | 2026-09-02 | 2026-09-03 |
| 3c473b74863e3a3f | F-2026-09-01-01 | bug | svg_to_pdf.dart,mermaid_renderer.html,issue-216-formula-export-blank.md | UNCHANGED | #216 | 2026-09-02 | 2026-09-02 |
| 758564f6e3c1ffb0 | F-2026-09-05-02 | tech-debt | import_zip_test.dart | NEW | N/A | 2026-09-05 | 2026-09-05 |
| a9f3c7d1e5b82044 | F-2026-09-05-01 | ci-infra | CI #840 android-emulator success, PR #254/#255/#256 | NEW | N/A | 2026-09-05 | 2026-09-05 |
| b04ac16ee32912cf | F-2026-09-05-01 | architecture | smoke_test.dart,phase35_home_smoke_test.dart | NEW | N/A | 2026-09-05 | 2026-09-05 |
| b2e8f4a6c9d13055 | F-2026-09-05-02 | ci-infra | tools/adi/test/import_zip_test.dart analyze errors | NEW | N/A | 2026-09-05 | 2026-09-05 |
| b86e4b47a1b958e1 | F-2026-09-07-01 | ci-infra |  | NEW | #263（新建） | 2026-09-07 | 2026-09-07 |
| da5fbded93636dd2 | F-2026-09-01-05 | architecture |  | UNCHANGED | N/A | 2026-09-02 | 2026-09-02 |
| e0d98ab667623d47 | F-2026-09-07-01 | tech-debt |  | NEW | #263 | 2026-09-07 | 2026-09-07 |
| e853e8f6a7cddfba | F-2026-09-02-02 | tech-debt | report.json,generate_report.py | WATCH | N/A | 2026-09-02 | 2026-09-02 |
| f5469b957182e6c2 | F-2026-09-01-02 | bug | formula_pdf_renderer.dart,word_exporter.dart | UNCHANGED | #216 | 2026-09-02 | 2026-09-02 |
| f5da01a687870462 | F-2026-09-07-02 | architecture | 0032-audit-frontier-incremental.md | RESOLVED | N/A | 2026-09-07 | 2026-09-07 |
| 14138cdee2a377b7 | F-2026-09-01-03 | test-gap | word_export_semantic_fidelity_test.dart | UNCHANGED | #234 | 2026-09-02 | 2026-09-02 |
| 2287adae59a02905 | F-2026-09-02-01 | regression |  | RESOLVED | #233 | 2026-09-02 | 2026-09-03 |
| 39c85d0b899f396b | F-2026-09-01-06 | architecture |  | RESOLVED | #215（已关闭） | 2026-09-02 | 2026-09-02 |
| 3bac87ff07c79bd3 | F-2026-09-01-04 | regression |  | RESOLVED | #233 | 2026-09-02 | 2026-09-03 |
| 3c473b74863e3a3f | F-2026-09-01-01 | bug | svg_to_pdf.dart,mermaid_renderer.html,issue-216-formula-export-blank.md | UNCHANGED | #216 | 2026-09-02 | 2026-09-02 |
| 4b67b7550074e8e3 | F-2026-09-08-02 | test-gap | provider_uniqueness_test.dart,providers.dart,editor_providers.dart | NEW | N/A | 2026-09-08 | 2026-09-08 |
| 758564f6e3c1ffb0 | F-2026-09-05-02 | tech-debt | import_zip_test.dart | NEW | N/A | 2026-09-05 | 2026-09-05 |
| a9f3c7d1e5b82044 | F-2026-09-05-01 | ci-infra | CI #840 android-emulator success, PR #254/#255/#256 | NEW | N/A | 2026-09-05 | 2026-09-05 |
| b04ac16ee32912cf | F-2026-09-05-01 | architecture | smoke_test.dart,phase35_home_smoke_test.dart | NEW | N/A | 2026-09-05 | 2026-09-05 |
| b2e8f4a6c9d13055 | F-2026-09-05-02 | ci-infra | tools/adi/test/import_zip_test.dart analyze errors | NEW | N/A | 2026-09-05 | 2026-09-05 |
| b86e4b47a1b958e1 | F-2026-09-07-01 | ci-infra |  | NEW | #263（新建） | 2026-09-07 | 2026-09-07 |
| be66c88ad7bf2c02 | F-2026-09-08-01 | architecture | document_provider.dart,document_service.dart,provider_uniqueness_test.dart | NEW | N/A（本次新建） | 2026-09-08 | 2026-09-08 |
| da5fbded93636dd2 | F-2026-09-01-05 | architecture |  | UNCHANGED | N/A | 2026-09-02 | 2026-09-02 |
| e0d98ab667623d47 | F-2026-09-07-01 | tech-debt |  | NEW | #263 | 2026-09-07 | 2026-09-07 |
| e853e8f6a7cddfba | F-2026-09-02-02 | tech-debt | report.json,generate_report.py | WATCH | N/A | 2026-09-02 | 2026-09-02 |
| f5469b957182e6c2 | F-2026-09-01-02 | bug | formula_pdf_renderer.dart,word_exporter.dart | UNCHANGED | #216 | 2026-09-02 | 2026-09-02 |
| f5da01a687870462 | F-2026-09-07-02 | architecture | 0032-audit-frontier-incremental.md | RESOLVED | N/A | 2026-09-07 | 2026-09-07 |
| 14138cdee2a377b7 | F-2026-09-01-03 | test-gap | word_export_semantic_fidelity_test.dart | UNCHANGED | #234 | 2026-09-02 | 2026-09-02 |
| 2287adae59a02905 | F-2026-09-02-01 | regression |  | RESOLVED | #233 | 2026-09-02 | 2026-09-03 |
| 39c85d0b899f396b | F-2026-09-01-06 | architecture |  | RESOLVED | #215（已关闭） | 2026-09-02 | 2026-09-02 |
| 3bac87ff07c79bd3 | F-2026-09-01-04 | regression |  | RESOLVED | #233 | 2026-09-02 | 2026-09-03 |
| 3c473b74863e3a3f | F-2026-09-01-01 | bug | svg_to_pdf.dart,mermaid_renderer.html,issue-216-formula-export-blank.md | UNCHANGED | #216 | 2026-09-02 | 2026-09-02 |
| 4b67b7550074e8e3 | F-2026-09-08-02 | test-gap | provider_uniqueness_test.dart,providers.dart,editor_providers.dart | NEW | N/A | 2026-09-08 | 2026-09-08 |
| 758564f6e3c1ffb0 | F-2026-09-05-02 | tech-debt | import_zip_test.dart | NEW | N/A | 2026-09-05 | 2026-09-05 |
| a9f3c7d1e5b82044 | F-2026-09-05-01 | ci-infra | CI #840 android-emulator success, PR #254/#255/#256 | NEW | N/A | 2026-09-05 | 2026-09-05 |
| b04ac16ee32912cf | F-2026-09-05-01 | architecture | smoke_test.dart,phase35_home_smoke_test.dart | NEW | N/A | 2026-09-05 | 2026-09-05 |
| b2e8f4a6c9d13055 | F-2026-09-05-02 | ci-infra | tools/adi/test/import_zip_test.dart analyze errors | NEW | N/A | 2026-09-05 | 2026-09-05 |
| b86e4b47a1b958e1 | F-2026-09-07-01 | ci-infra |  | NEW | #263（新建） | 2026-09-07 | 2026-09-07 |
| be66c88ad7bf2c02 | F-2026-09-08-01 | architecture | document_provider.dart,document_service.dart,provider_uniqueness_test.dart | NEW | N/A（本次新建） | 2026-09-08 | 2026-09-08 |
| da5fbded93636dd2 | F-2026-09-01-05 | architecture |  | UNCHANGED | N/A | 2026-09-02 | 2026-09-02 |
| e0d98ab667623d47 | F-2026-09-07-01 | tech-debt |  | NEW | #263 | 2026-09-07 | 2026-09-07 |
| e853e8f6a7cddfba | F-2026-09-02-02 | tech-debt | report.json,generate_report.py | WATCH | N/A | 2026-09-02 | 2026-09-02 |
| f5469b957182e6c2 | F-2026-09-01-02 | bug | formula_pdf_renderer.dart,word_exporter.dart | UNCHANGED | #216 | 2026-09-02 | 2026-09-02 |
| f5da01a687870462 | F-2026-09-07-02 | architecture | 0032-audit-frontier-incremental.md | RESOLVED | N/A | 2026-09-07 | 2026-09-07 |
| a1b2c3d4e5f60001 | F-2026-09-10-01 | test-gap | provider_uniqueness_test.dart | NEW | #265 | 2026-09-10 | 2026-09-10 |
| b2c3d4e5f6000102 | F-2026-09-10-02 | architecture | providers.dart,editor_providers.dart,document_provider.dart,editor_provider.dart | NEW | #266 | 2026-09-10 | 2026-09-10 |
<!-- REGISTRY_ROWS -->
