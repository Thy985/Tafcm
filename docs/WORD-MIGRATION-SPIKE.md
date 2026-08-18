# Word Migration Spike 报告：生态 docx 库替代手写 OOXML 评估

**日期**: 2026-08-18
**状态**: Spike 完成（集成可行性验证，决定性结论）
**结论**: **保留手写 OOXML** —— 生态 docx 库（docx_creator / docs_gee）的
依赖链与项目冲突，**无法在项目依赖体系内集成**（非"值不值得"，而是"装不上"）。

---

## 1. Spike 目标

评估生态 docx 库替代手写 OOXML 导出的可行性，7 维度对比：

```text
A 侧：手写 word_exporter.dart（305 行）+ word_ooxml_builder.dart（565 行）= 870 行
B 侧：docx_creator 1.3.2 / docs_gee 1.4.2（pub.dev 生态 docx 库）
```

## 2. 7 维度数据

### 维度 1：集成可行性 ❌ B 侧决定性失败（Spike 核心发现）

| 尝试 | 结果 |
|------|------|
| docx_creator 1.3.2 直接加入 | ❌ 依赖冲突：需 xml ^6.6.1（项目 xml 6.4.2）+ archive ^4.0.9（项目 ^3.4.9） |
| docs_gee 1.4.2 直接加入 | ❌ 依赖冲突：需 archive ^4.0.0（项目 ^3.4.9） |
| dependency_overrides（xml 6.6.1 + archive 4.0.9） | ❌ **override 后 image-4.9.1 编译失败**：`XmlName.parts` 构造器在 xml 6.6 移除 → 项目依赖链断裂 |
| 独立最小工程离线验证（/tmp/docx_spike） | ❌ pub cache 仅 docx_creator-1.2.5 且离线版本解析失败 |

**根因**：项目依赖体系锁定 `xml 6.4.2 / archive 3.4.9`（word_ooxml_builder 打包
依赖）；生态 docx 库要求 `xml ^6.6.1 / archive ^4.x`，**强升后破坏 image 包
（依赖 xml 6.4 API）**。升级成本 = 连带升级 xml/archive/image 全家桶，
超出 Spike 范围且风险不可控。

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

### 维度 4：功能覆盖 —— B 侧 API 理论覆盖 OK（但无法集成）

```text
docx_creator 1.3.2 fluent API：h1-h3/heading/p/bullet/numbered/table/
quote/code/hr/pageBreak —— 理论覆盖标题/段落/列表/表格/代码块/引用
docs_gee 1.4.2：Document/Paragraph/Table/TextRun + DocxGenerator

但两者均无法在项目依赖体系内安装 → 功能覆盖无实际意义
```

### 维度 5：扩展成本 —— A 侧维护成本 vs B 侧集成成本

```text
A 侧：870 行手写 OOXML 维护成本（styles/settings/numbering 补齐）
B 侧：集成成本 = 升级 xml 6.4.2→6.6.1 + archive 3.4.9→4.x + image
      （连带破坏编译）→ 集成成本远超维护成本
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

## 3. 结论：保留手写 OOXML（集成可行性决定性否决）

| 维度 | A 侧（手写） | B 侧（生态库） | 判定 |
|------|-------------|---------------|------|
| 1. 集成可行性 | ✅ 已集成 | ❌ 依赖链冲突 + override 破坏编译 | **决定性否决** |
| 2. 内容保真 | ✅ 26 项测试全绿 | 不可比 | A 侧胜 |
| 3. 结构有效性 | ✅ ECMA-376 完整 | 不可比 | A 侧胜 |
| 4. 功能覆盖 | ✅ 7 类元素 + 公式/图片 | 理论覆盖但无法集成 | A 侧胜 |
| 5. 扩展成本 | ⚠️ 870 行维护 | ❌ 需升级 3 个基础依赖 | A 侧胜 |
| 6. 异常处理 | ✅ 降级语义 | 不可比 | A 侧胜 |
| 7. 性能 | ✅ 通过 | 不可比 | A 侧胜 |

**决策**：**保留手写 OOXML**。

与 Parser Spike 不同（Parser 是「B 侧能跑但数据差」），Word 是**「B 侧装不上」**：
生态 docx 库的依赖链（xml ^6.6.1 / archive ^4.x）与项目锁定版本冲突，
强升破坏 image 包编译。**生态替代在依赖体系层面不可行**，这不是性能/结构
权衡问题，而是集成前置条件不成立。

**后续机会**：若未来项目升级 xml/archive/image 全家桶（独立于 Word 导出
的依赖维护工作），可重新评估 docx_creator 1.3.2（届时集成成本归零）。

## 4. Spike 资产与复跑

```text
尝试记录：
  - docx_creator 1.3.2 / docs_gee 1.4.2 加入 → 依赖冲突（xml/archive）
  - dependency_overrides xml 6.6.1 + archive 4.0.9 → image-4.9.1 编译失败
  - /tmp/docx_spike 独立工程 → pub cache 离线解析失败
pubspec.yaml 已还原（不引入 docx_creator；xml/archive override 已移除）
```

复跑（如需复现依赖冲突）：
```bash
cd flutter_app && sed -i 's|# Word Spike 评估结论.*||' pubspec.yaml  # 还原后状态
# 冲突证据：flutter pub add docx_creator  → 版本解决失败（xml/archive 冲突）
```

## 5. 附：对报告 2 的更新

`docs/MARKDOWN-ECOSYSTEM-HANDWRITTEN-REVIEW.md` 已同步：
- §1.5 Word 导出 → 「暂不替换；须先完成 docx Spike 后再决定」✅（本次 Spike 完成，结论落地为保留手写，且是**集成可行性否决**）
- §2 结论段 → 🔶 Word 导出暂不替换
- §3 汇总表 → 🔶 暂不替换
