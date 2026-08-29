# Testing Guide（测试指南）

> 怎么跑验证、怎么写测试——可执行命令与流程。
> 提炼自 [VERIFICATION-POLICY.md](../engineering/VERIFICATION-POLICY.md) 与 [Testing Principles](../principles/testing-principles.md)。

## 1. 怎么跑

```bash
cd flutter_app

# 全量（~1700 用例，3-5 min；Windows 分块）
flutter test

# 单文件（迭代首选）
flutter test test/parser/edge_case_test.dart

# 架构守门（改动涉及分层/文件访问时）
flutter test test/architecture/

# CLI 工具链（改 ffx 后必跑）
cd tools/ffx-cli && python -m pytest cli_anything/ffx/tests/
```

## 2. 测试分层速查

| 层 | 位置 | 覆盖 |
|----|------|------|
| Parser 单元 | test/parser/ | round-trip fuzz、edge case（含中文/GBK）、7 类元素 |
| 块渲染 Widget | test/presentation/blocks/ | 8 种 BlockType + inline spans + 交互 |
| 编辑器/协调器 | test/presentation/editor/ | 命令、撤销、focus、IME |
| 架构守门 | test/architecture/ | 分层依赖 / 文件访问 / Provider 唯一 / 文件规模 |
| 导出 | test/（exporter 相关） | PDF/Word/TXT 内容与元数据 |
| 可观测 | test/observability/ | ADI 采集、诊断导出、invariant |

## 3. 新功能/修复的测试要求

- **新功能**：必须有测试（单测或 Widget 测试）。
- **Bug 修复**：必须有回归测试（进 docs/regression/ 的 BUG case 包）。
- **禁止**：删除测试以通过 CI；`#[ignore]` / skip 隐藏失败（除非测试本身有 bug，需登记）。

## 4. Golden 基线操作

```bash
# 基线存放：flutter_app/test/golden/golden/*.png（28 个）
# 改显示文本/布局后：push 分支 → 触发 CI 的 update_goldens workflow
# → 下载 golden-baselines artifact → 覆盖 PNG → 提交
```

- Windows 本地不比对 golden（跨平台字体差异，GOLDEN-CI-001）；比对在 CI Linux 跑。
- 本地全量 `flutter test` 会跑 golden 并因基线差异失败——用 CI 排除项或单文件验证。

## 5. 已知超时 / flake

| 场景 | 应对 |
|------|------|
| ADI 写入 >120s | 中断重试 |
| E2E 全轮 18min / 单文件 50s | 后台跑 + 分段验证 |
| Gradle 偶发 Connection reset | 重跑即过 |
| 满载机器 perf/timing 测试失败 | 隔离复跑；与 CI 排除项对齐 |

## 6. 验证基线（发布判定）

- 证据等级：`synthetic < test < production < virtual < physical < visual < human_confirmed`。
- 发布门禁以真机（physical_device_runtime）+ visual 等级证据为准；模拟器 PASS ≠ 发布 PASS。
