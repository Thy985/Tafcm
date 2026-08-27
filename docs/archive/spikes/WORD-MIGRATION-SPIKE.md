# Word Migration Spike 报告：生态 docx 库替代手写 OOXML 评估

**日期**: 2026-08-18
**状态**: Spike 完成（集成可行性验证）+ 战略状态修正（评审反馈）
**结论**: **当前依赖基线下不迁移**；手写 OOXML 作为**临时稳定后端**保留，
同时将 **Word Export 标记为技术债**，并通过 **Export IR 隔离**，为未来
生态迁移保留出口。**不**将手写 OOXML 升级为「长期正确技术路线」。

---

## 0. 战略状态（评审修正，2026-08-18）

```text
Word Export
│
├─ 当前实现：手写 OOXML（word_exporter 305 行 + word_ooxml_builder 565 行）
│      ↓
│   能运行
│   但半成品
│   Bug 多
│   维护成本高
│
├─ 当前迁移：❌ 不可直接迁移
│      原因：依赖图冲突（xml 6.4.x / archive 3.x vs 候选库 xml ^6.6.1 / archive ^4.x）
│
└─ 长期策略：⚠️ 技术债，等待依赖基线重构后再次迁移评估
```

**关键区分**（本次修正核心）：

```text
「候选库在当前依赖图里装不上」  ≠  「手写 OOXML 是长期正确的技术路线」
```

Spike 只证明了前者（有效）；**没有证明**后者——Word 导出本身是半成品 +
Bug 多 + 维护成本高，长期维护成本可能高于迁移成本，这个命题甚至可能
是反过来的。

## 1. Spike 目标

评估生态 docx 库替代手写 OOXML 导出的可行性，7 维度对比：

```text
A 侧：手写 word_exporter.dart（305 行）+ word_ooxml_builder.dart（565 行）= 870 行
B 侧：docx_creator 1.3.2 / docs_gee 1.4.2 / docx_dart（观察对象）（pub.dev 生态 docx 库）
```

## 2. 7 维度数据

### 维度 1：集成可行性 ❌ B 侧当前依赖图冲突（有效结论，非永久否决）

| 尝试 | 结果 |
|------|------|
| docx_creator 1.3.2 直接加入 | ❌ 依赖冲突：需 xml ^6.6.1（项目 xml 6.4.2）+ archive ^4.0.9（项目 ^3.4.9） |
| docs_gee 1.4.2 直接加入 | ❌ 依赖冲突：需 archive ^4.0.0（项目 ^3.4.9） |
| dependency_overrides（xml 6.6.1 + archive 4.0.9） | ❌ **override 后 image-4.9.1 编译失败**：`XmlName.parts` 构造器在 xml 6.6 移除 → 项目依赖链断裂 |
| 独立最小工程离线验证（/tmp/docx_spike） | ❌ pub cache 仅 docx_creator-1.2.5 且离线版本解析失败 |

**根因**：项目依赖体系锁定 `xml 6.4.2 / archive 3.4.9`（word_ooxml_builder 打包
依赖）；生态 docx 库要求 `xml ^6.6.1 / archive ^4.x`，**强升后破坏 image 包
（依赖 xml 6.4 API）**。升级成本 = 连带升级 xml/archive/image 全家桶。

**注意**：这是**当前依赖基线**的结论。若项目未来升级 xml/archive/image
全家桶（独立于 Word 导出的依赖维护工作），集成成本归零，可重新评估。

### 维度 2：内容保真 —— A 侧已验证，B 侧无法运行

```text
A 侧（手写）：word_ooxml_builder_test + export_integration_test
            26 项全绿（heading/paragraph/list/code/quote/table/mermaid/
            公式 OMML 内容保真，ECMA-376 规范打包）
B 侧：无法在项目内编译运行 → 不可比
```

### 维度 3：结构有效性 —— A 侧已验证

```text
A 侧：OOXML parts 完整（styles/settings/numbering 补齐），
      archive/xml 打包，Word/WPS 兼容性由现有测试覆盖
B 侧：不可比（无法运行）
```

### 维度 4：功能覆盖 —— B 侧 API 理论覆盖 OK（但当前无法集成）

```text
docx_creator 1.3.2 fluent API：h1-h3/heading/p/bullet/numbered/table/
quote/code/hr/pageBreak —— 理论覆盖标题/段落/列表/表格/代码块/引用
docs_gee 1.4.2：Document/Paragraph/Table/TextRun + DocxGenerator

但两者均无法在当前依赖体系内安装 → 功能覆盖无实际意义
```

### 维度 5：扩展成本 —— A 侧维护成本 vs B 侧集成成本

```text
A 侧：870 行手写 OOXML 维护成本（styles/settings/numbering 补齐）
B 侧：当前集成成本 = 升级 xml/archive/image 全家桶（连带破坏编译）
     → 当前集成成本远超维护成本；但依赖基线重构后可归零
```

### 维度 6：异常处理 —— A 侧已验证

```text
A 侧：公式渲染失败降级（FormulaImageInfo 跳过 PNG）、
      Mermaid 渲染失败降级 —— 与 ADR-0007/0024 降级语义一致
B 侧：不可比
```

### 维度 7：性能 —— A 侧实测，B 侧不可比

```text
A 侧：word 导出集成测试通过（性能满足需求）
B 侧：无法运行
```

## 3. 结论（评审修正版）

| 维度 | A 侧（手写） | B 侧（生态库） | 判定 |
|------|-------------|---------------|------|
| 1. 集成可行性 | ✅ 已集成 | ❌ 当前依赖图冲突 | **当前不迁移** |
| 2. 内容保真 | ✅ 26 项测试全绿 | 当前不可比 | A 侧胜 |
| 3. 结构有效性 | ✅ ECMA-376 完整 | 当前不可比 | A 侧胜 |
| 4. 功能覆盖 | ✅ 7 类元素 + 公式/图片 | 理论覆盖但当前无法集成 | A 侧胜 |
| 5. 扩展成本 | ⚠️ 870 行维护（技术债） | ❌ 当前需升级 3 个基础依赖 | 待依赖基线重构 |
| 6. 异常处理 | ✅ 降级语义 | 当前不可比 | A 侧胜 |
| 7. 性能 | ✅ 通过 | 当前不可比 | A 侧胜 |

**决策（修正版）**：

> **当前依赖基线下不迁移**；手写 OOXML 作为**临时稳定后端**保留，
> 同时将 **Word Export 标记为技术债**（P1：用户可见 + Bug 多 + 维护困难，
> 进入 Product Reliability 而非继续「生态迁移问题」讨论），并通过
> **Export IR 隔离**，为未来生态迁移保留出口。
>
> **不**把「当前装不上」升级为「手写 OOXML 是长期正确的技术路线」——
> 该命题未被证明，且从现状看长期维护成本很可能高于迁移成本。

**候选库观察**（今日选的库未必是明年的库，不绑定单一第三方）：

| 库 | 版本 | 状态 |
|----|------|------|
| docx_creator | 1.3.2 | 快速迭代中（Word 兼容/图片/分页/长 URL 溢出修复），观察 |
| docs_gee | 1.4.2 | 纯 Dart，DOCX/PDF，声称 Word/WPS 兼容，观察 |
| docx_dart | — | 发布时间短、社区小，仅观察，不引入 |

## 4. 关键建议：Export IR 隔离（比争论手写/生态更重要）

不要让 Word 导出污染主编辑器架构。当前：

```text
DocumentElement → word_ooxml_builder → XML（直接绑定）
```

建议先定义稳定 Export IR：

```dart
ExportDocument
ExportNode / ExportParagraph / ExportTable
ExportList / ExportImage / ExportFormula / ExportCodeBlock
```

然后：

```text
FormulaFix AST
      ↓
DOCX Export Adapter
      ↓
Current OOXML Builder（可替换 Backend）
```

未来换库只换最后一层：

```text
FormulaFix AST
      ↓
DOCX Export Adapter
      ↓
docx_creator / docs_gee / 其他库
```

这样 xml/archive 升级或 docx 库成熟时，迁移成本大幅下降。

**技术债分层**：

```text
P0/P1（现在影响产品）：Word 导出巨大 bug + 用户可见 + 维护困难
                      → 进入 Product Reliability
P2（架构可替换性）：建立 Export IR，让手写 OOXML 成为可替换 Backend
```

## 5. 下一步：Word Export Audit（CAP-WORD-001~014）

不要凭感觉继续补 bug——直接建立与 Parser Batch 1 同方法的 Capability Audit：

```text
CAP-WORD-001 Heading          CAP-WORD-008 Formula OMML
CAP-WORD-002 Paragraph        CAP-WORD-009 Mermaid
CAP-WORD-003 Bold             CAP-WORD-010 Image
CAP-WORD-004 Lists            CAP-WORD-011 Page Break
CAP-WORD-005 Nested Lists     CAP-WORD-012 Word Compatibility
CAP-WORD-006 Table            CAP-WORD-013 WPS Compatibility
CAP-WORD-007 Chinese          CAP-WORD-014 Round Trip
```

```text
FFX capability audit
       ↓
发现真实 bug
       ↓
ADI / ADL（已跑通的闭环）
       ↓
修复
       ↓
Regression
```

**两种可能结果**：

```text
情况 A：现有 OOXML 功能覆盖 > 95%、Word/WPS 兼容好、剩余 bug 可控
        → 继续维护合理
情况 B：表格 × / 公式 × / 图片 × / 中文 × / WPS ×，且每修一个 bug
        都要改多个 OOXML part
        → 现有 exporter 已成为产品级技术债，需要重写
        （此时迁移不是「为了漂亮换库」，而是「现有 exporter 必须重写」）
```

## 6. Spike 资产与复跑

```text
尝试记录：
  - docx_creator 1.3.2 / docs_gee 1.4.2 加入 → 依赖冲突（xml/archive）
  - dependency_overrides xml 6.6.1 + archive 4.0.9 → image-4.9.1 编译失败
  - /tmp/docx_spike 独立工程 → pub cache 离线解析失败
pubspec.yaml 已还原（不引入 docx_creator；xml/archive override 已移除）
```

## 7. 附：对报告 2 的更新

`docs/MARKDOWN-ECOSYSTEM-HANDWRITTEN-REVIEW.md` 已同步：
- §1.5 Word 导出 → 「暂不替换；须先完成 docx Spike 后再决定」✅（本次 Spike 完成，结论落地为**当前不迁移 + 技术债 + Export IR 隔离**）
- §2 结论段 → 🔶 Word 导出暂不替换（技术债）
- §3 汇总表 → 🔶 暂不替换（等待依赖基线重构后再次迁移评估）
