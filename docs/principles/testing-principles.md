---
status: active
type: principle
owner: maintainers
last_reviewed: 2026-08-30
---

# Testing Principles（测试与验证原则）

> 回答"怎么证明它正确"。稳定条款，修改需 Human Owner 批准。
> 提炼源：docs/engineering/VERIFICATION-POLICY.md、AGENTS.md §13、GATE-REPORT。

## 1. 门禁即契约（与 CI 完全一致）

| 门禁 | 命令 | 备注 |
|------|------|------|
| Analyze | `flutter analyze --no-fatal-infos --fatal-warnings` | 裸 analyze 只把 warning 当 info，本地可能漏检 |
| Test | `flutter test` 全量（~1700 用例） | 本地受命令行长度限制时分块跑 |
| Build | `flutter build apk --debug` + `flutter build web` | 两平台 |
| Contract Sync | `ffx analyze contract-sync` | contracts/ 与能力矩阵自洽 |
| CLI | `tools/ffx-cli` pytest（170+ 用例） | 改 CLI 必跑 |

**提交前必须本地跑 analyze + 对应测试文件**——CI 不是唯一守门，本机是更早的一道闸。

## 2. 证据强度分级（发布判定依据）

```
synthetic < test_runtime < production_runtime < virtual_device_runtime
< physical_device_runtime < visual < human_confirmed
```

- 模拟器 PASS ≠ 发布门禁 PASS（语义偷换禁止）。
- 发布级结论必须标注证据等级；高等级证据优先。

## 3. 回归纪律

- 每个发现的 bug → regression asset（BUG case 包，docs/regression/）。
- 回归判定用 baseline failure set + fingerprint diff（四层 Failure Identity）。
- 既有失败 ≠ 新增回归；不得为了通过 CI 删除或 skip 测试（除非测试本身有 bug）。

## 4. 测试分层策略

- **单元/解析器测试**：parser round-trip fuzz、edge case 包（含中文/GBK）。
- **Widget 测试**：块渲染、编辑器交互、路由集成——必须注入 `AppTheme.lightTheme`（EditorTokens 依赖）。
- **架构守门测试**：分层依赖 / 文件访问 / Provider 唯一性 / 文件规模——架构约定必须有测试强制。
- **E2E（integration_test）**：真机 patrol 用例，约 50s/文件，全轮 18min，Gradle 偶发抖动可重跑。
- **Golden 基线**：Linux CI 生成，Windows 本地不比对（跨平台字体差异）；改基线走 `update_goldens` workflow。

## 5. 测试编写规范

- 新功能必须有测试；bug 修复必须有回归测试。
- 测试代码注入依赖用 `register({...})`（如 MarkdownExporter fake），不 mock 私有静态。
- 测试文件超过 400 行必须拆分；测试无豁免。
- 已知超时风险：ADI 写入可能 >120s 卡顿；E2E 全轮 18min——长测试后台运行 + 分段验证。

## 6. 验证基线参考

| 资产 | 位置 |
|------|------|
| 能力契约（机器可读） | contracts/*.json |
| 回归 case 包 | docs/regression/ |
| 证据（截图+判定） | docs/evidence/ |
| 视觉基线（golden） | flutter_app/test/golden/ |
| 工程基线 + 债务表 | docs/engineering/ENGINEERING-BASELINE.md |
