# Evidence Assets（证据资产）

**定位（L4 机器资产）**：可追溯的验证证据（截图 + 判定 + meta），供 FFX / ADI / CI 消费。
**原则**：证据可追溯——每个条目回指原始 RUN 报告（`archive/runs/`）。

## 子目录

| 目录 | 内容 | 来源 |
|------|------|------|
| `capability/` | 能力证据（E6 模拟器/真机渲染判定） | RUN-012~016 |
| `visual/` | 视觉证据（E8 截图 + Expected LaTeX → AST Diff 判定） | RUN-013~016 |
| `consumer/` | 消费端证据（Word/PDF 消费端验证） | RUN-007/011 |

## 视觉证据（visual/formula）

**语料本体在 `tools/ffx-cli/cli_anything/ffx/harness/vlm_corpus{,_physical}/`**——
被 ffx 测试硬编码引用（`test_e8_structure.py:26 CORPUS_DIR`），**不移动**，此处建立索引。

### 模拟器语料（vlm_corpus/，8 case）

| case | 截图 | 判定 |
|------|------|------|
| `f1_swap` | screenshot.png | FAIL / STRUCTURE_INVERSION（frac 颠倒） |
| `f2_wrong_sup` | screenshot.png | FAIL / binding mismatch（sup 归属） |
| `f3_missing` | screenshot.png | FAIL / MISSING_ELEMENT |
| `f4_crop` | screenshot.png | INCONCLUSIVE（截断） |
| `p1_emc2` | screenshot.png | PASS |
| `p2_frac` | screenshot.png | PASS |
| `p3_subsup` | screenshot.png | PASS |
| `p4_matrix` | screenshot.png | PASS |

### 真机语料（vlm_corpus_physical/，4 case，zorn / Android 16 / API 36）

| case | 来源 | 判定 |
|------|------|------|
| `p1_emc2` / `p2_frac` / `p3_subsup` / `p4_matrix` | commit 309666b 真机截图回传 | 4/4 PASS（physical_device_runtime） |

### 追溯

- 完整判定过程：`archive/runs/phase3.11/PHASE3.11-RUN-013~016`（E8 三层 Pipeline + Evaluator + VLM 结构模式）
- 证据等级：`contracts/formula.json` evidence_strength（synthetic < virtual_device_runtime < physical_device_runtime）
