# Experiment C-01 — CI 模拟器运行 device 级集成测试（Cross-Agent）

- **id**: C-01
- **date**: 2026-09-04
- **agent**: cline (via CI workflow) — Doubao 起草 workflow
- **environment**: github_actions (android-emulator-runner, api 34)
- **capability**: emulator_runtime / device_integration_test_execution
- **task**: 在 CI Android 模拟器上运行 Tafcm 已存在的 device 级 integration_test，验证"CI 能否真正构建并运行 APK"
- **setup**: 发现 8 个 device 级测试（IntegrationTestWidgetsFlutterBinding）从未在 CI 运行 → 起草 `android-device` job（PR #254）
- **steps**: 1) 探查发现 device 级测试被 CI 遗漏（test job 只扫 test/）→ 2) 起草 workflow（reactivecircus/android-emulator-runner@v2, api 34, pixel_5）→ 3) 最小版跑 smoke + home_smoke → 4) PR #254 待 Human 合入后触发
- **expected**: CI 模拟器上 smoke + home_smoke 通过（架构决策验证）
- **actual**: 草案已提交（PR #254）；**执行待 Human 合入后触发**——current status: awaiting-trigger
- **status**: partial（起草+PR done；执行 pending Human merge）
- **boundary**: type: policy — CI workflow 修改需 Human 合入（SUP-03）；合入后 Cline/CI 即可自主承担
- **failure_mode**: 待触发后观察（Gradle/AVD 下载耗时、device 测试环境级失败风险）
- **evidence**: PR #254 + ci.yml android-device job
- **evidence_strength**: production_runtime（合入触发后为真 CI 证据）
- **reproducibility**: 待验证
- **notes**: 若 C-01 通过 → emulator_runtime/device-UI 层可由 Cline(CI) 稳定承担；Doubao 则聚焦 APK 静态审计（B-01 proven）+ Web 代理视觉（需 setup）
