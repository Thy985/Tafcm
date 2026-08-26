# Migration Spike 报告：package:markdown 替代 Markdown Parser 评估

**日期**: 2026-08-18
**状态**: Spike 完成（A/B 7 维度数据采集，100 轮 fuzz corpus）
**结论**: **保留手写 Parser**（实验决策）——markdown 包解析成功率虽为 100%，但
AST 结构等价率仅 29%、round-trip 收敛率仅 40%、性能慢 2.15 倍，且公式需
自定义 InlineSyntax 扩展；在当前编辑模型需求下生态替代不划算。

---

## 1. Spike 目标与架构

评估 `package:markdown`（7.3.1）替代 FormulaFix 手写 Parser 的
「CommonMark/GFM 语法识别层」可行性：

```text
                    Markdown
                       │
                       ▼
             package:markdown
             CommonMark / GFM
                       │
              Adapter / Mapper（spike/markdown_package_adapter.dart）
                       │
                       ▼
              FormulaFix AST
                       │
              ┌────────┴────────┐
              │                 │
          Editor Core        Serializer
```

**A/B 基准**：现有 fuzz corpus（`MarkdownCorpusGenerator` seed=20260818，
100 轮）统一喂两路：
- A 侧：手写 `markdown_parser.dart` → FormulaFix AST
- B 侧：`package:markdown` 7.3.1（ExtensionSet.gitHubFlavored）→ Adapter → FormulaFix AST

## 2. 7 维度数据（原始：`SPIKE_AB_RESULT` JSON）

### 维度 1：解析成功率 ✅ 双方均 100%

```text
current_parser:    100/100（0 crashes）
markdown_package:  100/100（0 crashes）
```

markdown 包对现有 fuzz corpus 全部可解析，无崩溃。

### 维度 2：AST 结构等价率 ❌ B 侧仅 29%

```text
结构等价（顶层元素类型序列一致）: 29/100（29%）
结构不同: 71/100（71%）
```

主要差异来源（Spike 观察）：
- md 包列表项无 indent 概念 → ListElement 结构不同（手写 Parser 有
  nested/indent，md 包 li 无层级展开）
- md 包段落 inline 结构不同（Text/Emphasis/Strong 标签映射差异）
- 空代码块 / CRLF / 特殊字符处理差异
- 公式 `$...$` md 包按 Text 处理（未结构化）→ 段落结构不同

### 维度 3：B 侧 round-trip 收敛 ❌ 仅 40%

```text
fixpoint（serialize→parse 不动点）: 40/100（40%）
not_fixpoint: 60/100（60%）
```

B 侧经 Adapter → Serializer → 再 parse 后不能收敛——Adapter 丢信息
（列表 indent、公式结构化、inline 嵌套），序列化后无法还原。

### 维度 4：GFM 覆盖 ✅ 基础语法支持良好

```text
mermaid_blocks（识别）: 14/100 轮
task_items:             17/100 轮
tables:                 26/100 轮
formula_as_text（观察）: 53 轮含 $（md 包按 Text 处理）
```

GFM 表格 / 任务列表 / 代码块基础识别 OK；**公式需自定义 InlineSyntax**。

### 维度 5：自定义扩展成本 ⚠️ 中等偏高

| 扩展点 | 方式 | 成本评估 |
|--------|------|---------|
| Formula `$...$` | 自定义 InlineSyntax（onMatch 解析 + 挂载到 inlineSyntaxes） | 需实现公式词法（latex 内容提取 + displayMode）——约 40-60 行 |
| Mermaid ` ```mermaid ` | 自定义 BlockSyntax（canParse 检测 language） | 约 15-25 行 |
| TaskList `- [x]` | md 包已支持（GFM checkbox） | 0 行（已覆盖） |
| 降级容错（单行错误 → Paragraph） | 无直接对应 | 需在 Adapter 层 try/catch 包裹——约 10 行 |

公式 + Mermaid + 降级合计约 **65-95 行扩展**，加 Adapter 本身（本次 ~204 行），
总映射层约 **270-300 行**——**高于手写 Parser 的领域映射复杂度预期**。

### 维度 6：异常降级行为 ⚠️ 需 Adapter 层补充

手写 Parser 有 P1 B-5 单行降级（错误行 → ParagraphElement，保留原文）。
markdown 包本身对非法语法容错较强（不抛异常），但**无「降级为段落保留原文」
语义**——需要 Adapter 层 try/catch 补充，且 md 包 AST 已丢失原始行信息
（textContent 拼接后无法逐行恢复），降级保真度低于手写。

### 维度 7：性能 ❌ B 侧慢 2.15 倍

```text
current_parser 平均:   791 µs/文档
markdown_package 平均: 1700 µs/文档（2.15× 慢）
```

markdown 包 AST 构建 + Adapter 映射双重开销；手写 Parser 单遍解析更快。
对编辑器（输入实时解析）是实质劣势。

## 3. 结论：保留手写 Parser（实验决策）

| 维度 | 结果 | 判定 |
|------|------|------|
| 1. 解析成功率 | 双方 100% | ✅ 平 |
| 2. AST 结构等价 | 29% | ❌ B 侧劣 |
| 3. round-trip 收敛 | 40% | ❌ B 侧劣 |
| 4. GFM 覆盖 | 基础语法 OK，公式缺失 | ⚠️ B 侧需扩展 |
| 5. 扩展成本 | 需 ~270-300 行映射层 | ⚠️ 偏高 |
| 6. 降级行为 | 无逐行保留语义 | ❌ B 侧劣 |
| 7. 性能 | 2.15× 慢 | ❌ B 侧劣 |

**决策**：**保留手写 Parser**。

理由（实验数据支撑，非经验判断）：
1. **AST 结构等价率仅 29%** —— md 包 AST 与 FormulaFix 编辑模型结构差异大
   （无 indent/nested、inline 标签映射不同），Adapter 需大量特殊转换
2. **round-trip 收敛率仅 40%** —— 编辑模型的核心不变量（parse→serialize→
   parse 保真）在 B 侧严重退化
3. **性能 2.15× 慢** —— 编辑器实时解析场景不可接受
4. **公式需自定义 InlineSyntax**（+40-60 行）且 md 包无「单行降级保留原文」
   语义——自定义语法与容错需求恰是手写 Parser 已解决的问题

**边界说明**：Spike 使用最简 Adapter（顶层映射），未实现完整 nested/indent
映射——但即便补全，结构等价率与 round-trip 收敛的**根本差异**（md 包
无编辑模型语义）不会消除。若未来编辑器改为「渲染器模式」（只读展示），
可重新评估 flutter_markdown/markdown 包；**编辑模型路线下保留手写**。

## 4. Spike 资产

```text
flutter_app/test/parser/spike/
  markdown_package_adapter.dart      # B 侧 Adapter（~204 行，按 tag 分发）
  spike_ab_comparison_test.dart      # A/B 对比测试（100 轮 + 公式观察点）
```

复跑：
```bash
cd flutter_app && flutter test test/parser/spike/spike_ab_comparison_test.dart
# 输出 SPIKE_AB_RESULT JSON + SPIKE_FORMULA_AS_TEXT 观察
```

## 5. 附：对报告 2 的更新

`docs/MARKDOWN-ECOSYSTEM-HANDWRITTEN-REVIEW.md` 已同步：
- §1.1 Parser 结论 → 「暂不替换；须先完成 Spike 后再决定」✅（本次 Spike 完成，结论落地为保留手写）
- §2.1 新增 Migration Spike 计划 ✅
- §3 汇总表 Parser 行 → 🔶 暂不替换
