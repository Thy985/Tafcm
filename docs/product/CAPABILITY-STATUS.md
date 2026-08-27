# Capability Status（能力完成度）

**定位（L2 Current State Truth，人类视图）**：FormulaFix 当前能力完成度。
机器视图见 [contracts/*.json](../../contracts/)（ffx 消费）；本页为人类可读汇总。

**数据源**（历史完整矩阵，已归档保留）：
- [CAPABILITY-STATUS-source-coverage.md](CAPABILITY-STATUS-source-coverage.md)（S0-S5 能力覆盖矩阵，2026-08-19）
- [CAPABILITY-STATUS-source-completion.md](CAPABILITY-STATUS-source-completion.md)（E0-E8 完成证据矩阵，2026-08-19）

---

## 能力族完成度（Phase 3.11 EXIT 判定，2026-08-22）

| 能力族 | 能力 | 状态 | 证据 |
|--------|------|------|------|
| **F1 Data** | Markdown 解析 / 序列化 | ✅ VALIDATED | Golden Loop（RUN-002/003）+ fuzz 2001 轮 |
| **F2 Behavior** | Undo / Transaction / IME | ✅ VALIDATED | Undo Golden Loop（RUN-008） |
| **F3 Runtime** | Formula 渲染 | ✅ VALIDATED | Real Defect Loop（RUN-010）+ E6 真机截图 |
| **F4 Consumer** | Word / PDF 导出 | ✅ VALIDATED | Full Golden Loop（RUN-011）+ PDF Real Defect（RUN-007） |
| **E6/E8 证据** | 物理运行 / 视觉语义 | ✅ RELEASE-GATE SATISFIED | 真机 zorn 4/4 PASS + E8 Evaluator/VLM（RUN-012~016） |

## 产品能力明细（人类速览）

| 能力 | 完成度 | 说明 |
|------|--------|------|
| Markdown 解析 | S4 Round-trip | 手写 parser，fuzz 锁死 BUG-1~6 |
| 块级 WYSIWYG 编辑 | S5 Runtime | 8 种 BlockType + Transaction |
| 公式渲染 | S5 Runtime | LaTeX → SVG + PNG 回退 |
| Mermaid | S4 | WebView 渲染 → SVG 导出 |
| 导出（Word/PDF/MD） | S5 | 消费端验证 |
| 主题（Light/Dark/Sepia） | S3 | Design Token 驱动 |
| 可观测 / ADI | ✅ | ADR-0024 v0.1/v0.2 |

## 已知边界（不宣称完成）

- Visual/Product Identity ~60%（UI 修复 P2-P3 进行中）
- 完整 SSIM/感知距离管线（E8.3 升级）未接入
- 云端 VLM 后端未接（qwen2vl-local 已实现）

详细逐项判定：见 source 矩阵 + [ENGINEERING-BASELINE](../engineering/ENGINEERING-BASELINE.md)。
