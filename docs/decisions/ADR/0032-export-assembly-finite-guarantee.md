# ADR-0032: Export Assembly Finite Guarantee —— 导出拼装阶段有限性保证

- **状态**：Proposed（待 Human Owner 审批）
- **生效日期**：待定
- **决策者**：Human Owner + 首席架构工程师
- **关联**：ADR-0022（渲染降级语义）/ PR-3（进度与质量分离）/ Bug4 专项（真机卡 28%）

## 背景

真机「卡 28%」专项（2026-08-31）经完整差分实验定位 blocking primitive：

| 实验 | 结果 | 结论 |
|------|------|------|
| B-1 分片（30 块/片） | 第一片仍永久卡死 | 分片假设**否定** |
| B-2 纯 Dart 复现（118 真实 SVG + 手写复杂 SVG） | 全部 1s 内完成 | SVG 内容/解析器/转换器死循环**排除** |
| B-3 真机差分 A/C/C+（30 块 ± 1 公式） | 116-140ms 全部完成 | 字体/大页面/单公式**排除** |
| B-3 真机差分 E（30 块 + 12 公式 SVG） | **addPage 永久卡死** | **多公式 SVG 密度 = blocking primitive**（真机环境特有，纯 Dart 同密度 30s 内完成） |

**核心问题**：`pdf.addPage(pw.MultiPage(...))` 是 dart_pdf 的同步调用（`addPage → page.generate → MultiPage.layout`），在主 isolate 同步执行全部块布局。当片内含多个公式 SVG 时，真机环境（字体嵌入 / 内存 / WebView 残余差异）可使其**永久阻塞**，且：

1. `addPage` 无法 await / 无法中断 → 包围它的 `try/finally` 无法触发
2. Export Future 永不进入 terminal state → `runWithGuard` 的收口（PR-3 终态审计）形同虚设
3. UI 冻结在最后一次成功帧（'渲染公式 39/118'），用户无法感知进度

## 决策

**Export assembly 阶段必须满足有限性（finite）保证**：任何导出阶段，无论根因是否已明，都必须能进入 terminal state（`SUCCESS / FALLBACK / FAILED / CANCELLED`），不得存在无限等待。

### 1. addPage Watchdog（强制终止 + 降级）

- 每个 `pdf.addPage` 调用用 watchdog 包裹：布局超时（草案值 10s，与公式渲染超时一致）后**放弃该页同步布局**，将该页标记为 `assembly_blocked`。
- 降级策略（按 ADR-0022 渲染降级语义）：
  1. 该页公式 SVG → 文本 fallback（最保守，保证 PDF 可生成）
  2. 或该页整体标记 FALLBACK，导出继续下一页
- watchdog 超时后导出**必须**继续（跳过问题页），最终进入 `SUCCESS(with fallback)` 或 `FAILED`。

### 2. Per-Page Diagnostics（已在 B-3 落地，纳入正式观测）

- 分片 addPage 前输出 `slice manifest`（块类型构成 + CJK font 状态 + 时间戳）——已实现（`BlockLc slice_$s manifest=[...]`）。
- watchdog 触发时输出：卡死页 index / 构成 / 超时时长，进入 ADI 诊断链（ADR-0024）。

### 3. Terminal State 契约（架构原则沉淀）

> **任何 Export Stage 都不得存在无限等待；根因未明也必须能够进入 terminal state。**

- 该原则进入 Export Contract / FFX Capability Contract（`ffx capability verify formula-export` 增加 `assembly_finite` 检查项）。
- `runWithGuard` 收口保证（PR-3）覆盖到 assembly 阶段：即使 `addPage` 内部永久阻塞，watchdog 兜底保证 Future 可完成。

## 动机

1. **架构性缺陷独立于根因**：即使未来证明是 CJK 字体 / 内存 / dart_pdf 绘制问题，也不应允许导出无限卡死。
2. **可诊断性**：卡死时用户与 Agent 至少得到"哪一页 / 什么构成 / 超时多久"的观测，而非"进度停 28% 无日志"。
3. **与既有契约一致**：PR-3 已确立进度单调 + 终态收口 + 进度/质量分离；本 ADR 把"有限性"补为 assembly 阶段的硬约束。
4. **阻断 P0-5/6 验收**：FORMULA-EXPORT-001 回归资产要求导出可完成；无限卡死直接违反验收守门。

## 后果

### 正面
- 导出永不无限卡死（有 watchdog 兜底）。
- 卡死信息进入诊断链（page index / manifest / 时长）。
- 质量降级可观测：`FormulaQuality` 反映 fallback 分布（PR-3 已分离进度/质量）。

### 负面 / 代价
- watchdog 依赖"主 isolate 能响应定时器"——若 `addPage` 的同步布局**完全饿死事件循环**（连 timer 回调都不执行），watchdog 无法触发。**这是本方案的已知边界**，需实测验证（dart_pdf 布局是纯 Dart 计算，通常不饿死 timer；若实测饿死，需降级为 isolate 隔离或逐块布局）。
- 降级后 PDF 质量下降（公式文本化/页面跳过），需在 FormulaQuality 明确报告。
- 超时阈值需真机校准（10s 草案值，避免误伤正常慢页）。

### 验证方式
- 单测：mock 一个"永久阻塞的 addPage"（注入假 widget 触发布局死循环），断言 watchdog 超时后导出进入 terminal state（FALLBACK/FAILED）而非永久挂起。
- 真机：Case E（30 块 + 12 公式，当前必卡）验证 watchdog 触发 + 导出完成（质量降级）。

## 替代方案

| 方案 | 评估 |
|------|------|
| **isolate 隔离 PDF 布局** | dart_pdf `Document`/`Context` 不可跨 isolate 传递（内存布局对象），不可行 |
| **继续缩小分片（30→8-10 块）** | B-3 证明非块数规模问题（30 块纯文本 140ms 正常），缩片不解决多公式密度卡死，**否定** |
| **SVG Safety Gate（复杂度检查分流 PNG）** | B-2 证明纯 Dart 路径 118 真实 SVG 全过，SVG 内容非死循环触发点，gate 拦不住真机环境问题，**暂缓**（根因未明时不做） |
| **公式 PNG 降级（真机导出全走 PngPlan）** | 有可靠性价值但**需实测门槛**：真机 SVG path vs PNG path 对照（SVG=hang / PNG=pass 才升级为正式修复），本 ADR 的 watchdog 为兜底，PNG 降级作为根因修复候选 |
