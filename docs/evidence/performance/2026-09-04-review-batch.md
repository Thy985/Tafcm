# 性能审查批次收口证据（2026-09-04 审查 #245-#250）

证据登记（evidence registration），非发布门记录。
收口日期：2026-10-02。
审查批次：2026-09-04 性能审查提出的 #245 / #246 / #247 / #248 / #249 / #250。

## 1. 结论汇总

| Issue | 主题 | 状态 | 落地 PR | 证据等级 |
|-------|------|------|---------|---------|
| #245 | wordCount 每次按键 O(n²) 全文档序列化 | CLOSED | PR #280 | `test_runtime` |
| #246 | 每次按键 EditorShell 整树重建 | CLOSED | PR #300 | `test_runtime` |
| #247 | 块查找 O(n) + undo/redo 放大 | CLOSED（拆分） | PR #299（前半）+ #301（后半） | `test_runtime` |
| #248 | 导出无全局超时 | CLOSED | PR #298 | `test_runtime` |
| #249 | 自动保存全量序列化 | CLOSED | PR #298 | `test_runtime` |
| #250 | Word 导出公式/Mermaid 串行渲染 | **OPEN（降级 P3）** | — | — |

合入 `main` 的 commit：

- #245 → PR #280（2026-09-12 合并）
- #246 → `525ddcc`（PR #300，2026-10-01 合并，含 8 个跟进修复 commit）
- #247 → `408884e`（PR #299，2026-10-01 合并）
- #248 / #249 → `a939a91`（PR #298，2026-09-30 合并）

## 2. 证据等级诚实声明

**本批次全部 6 项的最高证据等级均为 `test_runtime`，无一例外。**

依据 [VERIFICATION-POLICY.md](../../../engineering/VERIFICATION-POLICY.md) §证据等级（RUN-013 冻结）：

```
synthetic < test_runtime < production_runtime < virtual_device_runtime
< physical_device_runtime < visual < human_confirmed
```

### 2.1 未达成的等级

- **未做真机 / 模拟器运行时验证**。#245 / #246 / #247 / #250 原 issue 均带
  `needs-device-validation` 标记，但至今未在真机或模拟器上实测修复后的帧率、
  导出耗时与输入延迟。
- **未跑 E2E Release Gate**（`integration_test/` 全轮 ≈ 18min）。该门禁触发条件为
  「打 release tag 前 / 发布 APK 前 / 合并 `release-candidate` PR 前」，性能修复 PR
  不触发该门禁——不是遗漏，是制度上不适用。

### 2.2 为何不声明更高等级

修复的正确性主要由以下确定性证据支撑，而非设备实测：

- 结构性守门测试（复杂度断言，见 §3）
- 既有 widget / 单元测试全绿
- `flutter analyze --no-fatal-infos --fatal-warnings` 无 error / warning

这些属于 `test_runtime`。按 VERIFICATION-POLICY「Emulator PASS ≠ release gate PASS
（语义偷换禁止）」，即便日后补跑模拟器也不得据此宣称达到 release gate 等级。

结论：**性能收益的真实幅度（快了多少 ms / 多少 fps）目前无设备级数据支撑。**
本记录只证明「退化已被结构性守门拦住」，不证明「提速幅度达到某数值」。

## 3. #247 结构性守门（本次收口新增）

新增文件 `flutter_app/test/performance/block_lookup_scaling_test.dart`，
守门 PR #299 引入的 `Map<BlockId, _Entry>` 块索引（O(1)）不得退化回 O(n)。

### 3.1 为什么不用 `perf_baseline.json` 的绝对 ms 棘轮

现有 U5 ratchet 模型是「median ≤ baseline × slack」的绝对耗时断言。
O(1) 哈希查找单次实测约 **0.014-0.02us**，被计时器噪声与循环开销完全淹没——
`perf_baseline.json` 无法区分 O(1) 与 O(n)，两者都能轻松通过。
绝对值棘轮在此场景只会制造 flake，不会报警。

### 3.2 采用「规模比」断言

对块数相差 16× 的两个编辑器（250 / 4000 块）各做**相同次数**的查找，
取单次耗时之比：

- O(1) → 比值 ≈ 1
- O(n) → 比值 ≈ 16

阈值 **3.0**（距 O(n) 理论值 16 有 5× 余量）。

比值是同进程内的相对量，跨机器可比，且与 `perf_baseline.json` 的机器基线解耦——
不需要在参考机器上重测基线，也不受 AOT / JIT 差异影响。

### 3.3 实测数据（local dev / Windows / debug JIT）

取每组 5 轮的**最小值**（干扰只会让耗时变长，故最小值信噪比最高）：

| 场景 | 实测比值区间 |
|------|------------|
| `getBlock` | 0.81 – 1.28 |
| `updateBlockContent` | 0.65 – 1.24 |
| **O(n) 反向验证**（临时改回线性扫描） | **20.23 → 测试 FAIL** |

反向验证是本守门可信的关键证据：确认它在真实退化时确实会红，而非恒过的摆设。

早期版本用「两轮均值」时 `updateBlockContent` 比值在 1.18~2.32 间抖动，
阈值 3.0 仅剩 1.3× 余量（flake 风险）；改为 5 轮取最小值后收敛到 0.65~1.24。

### 3.4 未采用绝对值 ratchet 的连带影响

#246（EditorShell 重建次数）同样未新增 perf_baseline 指标。重建**次数**是
确定性计数而非耗时，本就不适配 ratchet 的计时 schema，且已由
`test/presentation/editor/editor_local_refresh_widget_test.dart` 的 BuildCounter
确定性覆盖。故本批次只新增 1 个结构守门，不扩到 2 个。

## 4. 遗留工作

| Issue | 内容 | 处置 |
|-------|------|------|
| #301 | undo/redo 逐条 op 整块重解析放大；含 `cachedIndex` 每次 `apply` 的无用 O(n) 扫描 | 保持 OPEN（P2） |
| #250 | Word 导出公式/Mermaid 串行渲染（`_maxConcurrent=4` 名不副实） | 保持 OPEN（P2 → **P3**） |

### 4.1 #247 关闭时的更正记录

PR #299 描述称「`indexOf`: O(n)→O(1)」，此说法不准确：`_ids` 仍是
`List<BlockId>`（`in_memory_document_editor.dart:29`），`indexOf`（`:109`）实为 O(n)。
该偏差已在 #247 关闭评论中更正，并由 `block_lookup_scaling_test.dart`
第三个用例显式记录，防止后人误当成契约。

另发现 `edit_operation.dart:107` 每次 `apply` 执行
`cachedIndex = editor.indexOf(blockId)`，但全仓检索确认 `cachedIndex`
**在生产代码中从未被读取**（`:82` / `:114` 注释写明「不依赖 cachedIndex」），
仅有测试断言其被填充——即每次按键白付一次 O(n) 扫描。跟进见 #301。

### 4.2 #250 降级理由

- 原描述「无超时 → 永久挂起」已由 PR #298 的 **120s 全局超时**修复，
  失败模式从「不可恢复的卡死」降为「有界且可恢复」；
- 剩余「大文档导出慢」需重构渲染层（批量提交渲染单元），超出本批次最小改动范围。

## 5. 附：CI 门禁现状（本次收口顺带发现，非本 PR 修改范围）

`.github/workflows/ci.yml` 的 perf job 执行 `flutter test --tags perf`，
主 test job 执行 `--exclude-tags golden --exclude-tags perf`。但实测标注情况为：

| 文件 | `@Tags(['perf'])` | 实际跑在 |
|------|------------------|---------|
| `list_perf_test.dart` | 有 | perf job |
| `perf_ratchet_test.dart` | **无** | **主 test job** |
| `block_perf_test.dart` | **无** | **主 test job** |
| `parser_perf_test.dart` | **无** | **主 test job** |

即 ci.yml 第 208-211 行注释描述的「TC-PERF-1/2/3 绝对阈值 + U5 ratchet
基线由 perf job 接管」与实际标签不符——这三者目前由主 job 执行。

本次新增的 `block_lookup_scaling_test.dart` **刻意不加 `perf` tag**：
它是纯 Dart、无 I/O、阈值余量 2.3× 的确定性守门，应留在阻塞性的主
test job，而非可绕过的 perf job。

标签错配的修正涉及 CI 门禁语义变更（可能让 CI 转红），留待独立 PR 处理。

Task scope: ROADMAP 性能审查 2026-09-04（#245-#250 收口）
