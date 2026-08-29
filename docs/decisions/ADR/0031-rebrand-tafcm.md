# ADR-0031: 品牌改名 —— FormulaFix → Tafcm

- **状态**：Accepted
- **生效日期**：2026-08-29
- **决策者**：Human Owner（applicationId 决策）+ 首席架构工程师（评估）
- **Supersedes**：ADR-0001 §1（项目命名条款；§2 目录结构条款保留）

## 背景

FormulaFix 自 Phase 0 起作为项目名使用，随 Phase 0-3.11 完成、产品进入"社区发布 + 反馈迭代"空档期（2026-08-29 决策），品牌定位需重新审视：

1. **"Fix" 语义负面**：有"修复 / 补救"暗示（修坏了的东西），不是产品愿景语言。
2. **覆盖面窄**：只表达"公式"，未表达排版 / Markdown / CLI / Agent 四个实际能力。
3. **发布前改名成本最低**：`applicationId` 一旦对外发布即不可变（全新应用身份），现有用户无法覆盖升级。当前仅 6 月 debug APK 外流、无真实用户，是改名窗口期。

2026-08-29 评估确认五维定位均有真实代码支撑（见 §动机）。

## 决策

### 1. 品牌名

**Tafcm**，展开为五个产品支柱：

| 字母 | 词 | 定位 | 代码支撑 |
|------|-----|------|---------|
| T | **Typeset** | 排版优先：用户看到的是 Document 而不是 Block（Typora 化） | WYSIWYG 双态、serif 排版体系、UX-GUIDE v2.0 |
| A | **Agent-native** | Agent 可诊断、可驱动的文档工具 | ADI（ADR-0024）、issue triage agent（ADR-0025）、可观测体系 |
| C | **CLI-native** | CLI 优先的文档处理 | `tools/ffx-cli`（170+ 测试）、`tools/adi/adi.dart` |
| F | **Formula-aware** | LaTeX 公式为差异化主轴 | LaTeX → SVG 矢量 + PNG 回退、PDF 公式矢量硬约束 |
| M | **Markdown-first** | .md 单一真相源，任意来源即开即看 | ADR-0003、ACTION_VIEW 查看器、GBK/UTF-8 解码兜底 |

### 2. 命名规范

| 场景 | 规范 |
|------|------|
| 品牌名（用户可见） | `Tafcm`（PascalCase，专有名词） |
| Dart 包名 / pubspec | `tafcm` |
| 文件名前缀（诊断 zip 等） | `tafcm_` |
| Android applicationId / namespace | `com.tafcm.app`（Human Owner 决策，发布后不可变） |
| MethodChannel | `tafcm.app/external_file` |

### 3. 范围

- **L0 显示名 + L1 代码层**（PR #177，2026-08-29 已合入）：Android label、MaterialApp title、首页字标、PDF/Word 导出元数据、pubspec name、903 处 import、applicationId/namespace、MainActivity 迁移、MethodChannel、ffx-cli / issue-triage 工具链、README CI badge。
- **L2 叙事文档**（本 ADR + 2026-08-29 文档轮）：README / PRODUCT / UX-GUIDE / ROADMAP / AGENTS.md 定位叙事。
- **兼容保留**：`formula_fix_documents.json` / `formula_fix_autosave.md`（legacy 迁移文件名，改则破坏迁移）；docs/archive、docs/contracts 冻结档案内历史引用。

## 动机

1. **移除负面语义**：从"修复公式"转向"排版 + 公式 + Markdown 的创作工具"。
2. **叙事与能力对齐**：A/C 两维此前是内部工程能力，改名为其提供产品叙事入口（ADI、ffx-cli 从"工具"升级为"支柱"）。
3. **发布前锁定身份**：`com.tafcm.app` 一经发布不可改，改名字段（applicationId / Dart 包名）必须先于社区发布完成。

## 后果

### 正面

- 品牌名可承载完整产品愿景，摆脱"公式修复"窄定位。
- 与 GitHub 仓库新名（`Thy985/Tafcm`）一致，CI badge / issue-triage 引用已同步。

### 负面 / 代价

- 旧名认知断裂：既有文档、issue、PR 中的 FormulaFix 引用不再指向新名（历史记录保留原文）。
- 名称机械替换量大：L1 涉及 903 处 import + 14 处类名 + Android 源文件迁移（已完成并通过 analyze / 全量测试 / apk 构建验证）。
- `applicationId` 变更 = 全新应用身份：旧 debug APK 安装无法覆盖升级（无真实用户，可接受）。

### 风险缓解

- legacy 存储文件名不改，迁移路径（ADR-0003）不受影响。
- 仓库重命名由 GitHub 自动重定向旧链接。

## 替代方案

1. **保留 FormulaFix**：否定——"Fix" 负面语义 + 覆盖窄。
2. **TAFCM 全大写**：否定——品牌名按专有名词 PascalCase 处理，全大写仅用于 logo 场景。
3. **其他候选名**（Tafix / TypoFix / FixNote 等）：均未达到"五维可展开 + 无负面语义"的标准。

## 参考

- 评估报告：2026-08-29 品牌改名评估（会话产物，未入库）
- PR #177（L0+L1 代码层，已合入）、PR #180（CI import 修复，已合入）
- 本 ADR 使 ADR-0001 §1 的命名决策失效（Superseded）
