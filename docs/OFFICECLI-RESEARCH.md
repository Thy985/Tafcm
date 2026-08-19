# OfficeCLI 调研报告（Agent-native Office 文档工具）

**日期**: 2026-08-19
**调研对象**: [iOfficeAI/OfficeCLI](https://github.com/iOfficeAI/OfficeCLI)（v1.0.144，28.7K star）
**关联**: DOCX QA Pipeline（CAP-WORD-A~G）/ wpscli 对比 / CAP-WORD-F 视觉缺口

---

## 1. 定位

**OfficeCLI = 面向 AI Agent 的 Office 套件**：读取、编辑、自动化 Word/Excel/PPT。
单二进制分发、免费开源、**无需安装 Microsoft Office**、无运行时依赖（.NET 内嵌）。

```text
give any AI agent full control over Word, Excel, PowerPoint — in one line of code
```

## 2. 核心能力

### 2.1 三层架构（由浅入深，Agent 渐进使用）

| 层 | 用途 | 命令 |
|----|------|------|
| **L1 Read** | 语义视图（读大纲/统计/问题/渲染） | `view`（text/annotated/outline/stats/**issues/html/svg/screenshot/pdf**） |
| **L2 DOM** | 结构化元素操作（按路径增删改查） | `get` / `query` / `set` / `add` / `remove` / `move` / `swap` |
| **L3 Raw XML** | XPath 直接访问（逃生舱） | `raw` / `raw-set` / `add-part` / `validate` |

### 2.2 格式支持

```text
Word (.docx)      ✅ Read / Modify / Create
Excel (.xlsx)     ✅ Read / Modify / Create（350+ 函数自动求值、透视表）
PowerPoint (.pptx)✅ Read / Modify / Create（动画/3D glb/morph/缩放）
```

### 2.3 自带高保真渲染引擎（keystone）

```text
渲染 .docx/.xlsx/.pptx → HTML 或 PNG（view html / view screenshot）
覆盖：形状/图表（趋势线/误差线/瀑布/K线/迷你图）/
      公式（OMML → LaTeX，KaTeX 渲染）/ 3D glb（Three.js）/
      morph 过渡/幻灯片缩放/形状效果
每页 PNG 截图：渲染 HTML → headless 浏览器 → PNG
```

**关键意义**：Agent 可以「看」到渲染结果（喂多模态模型或读 HTML 结构），
闭合 **render → look → fix** 循环——这是 wpscli 缺的能力。

### 2.4 Agent 集成

```text
MCP Server：officecli mcp claude / cursor / vscode / lmstudio（JSON-RPC 工具暴露）
Skill 安装：officecli install 自动检测 Claude Code/Cursor/Windsurf/GitHub
            Copilot/Codex，注入 skill 文件（SKILL.md 239 行 / 8K tokens）
确定性 JSON：所有命令支持 --json，统一 schema，无需 regex 解析
路径寻址：/slide[1]/shape[2]（1-based，Agent 无需懂 XML 命名空间）
自愈工作流：validate / view issues / 结构化错误码（not_found /
            invalid_value / unsupported_property）+ 建议与合法范围
```

### 2.5 其他

```text
open/close 常驻模式：3+ 步操作零文件 I/O（OFFICECLI_RESIDENT_FLUSH 调优）
watch 实时预览：浏览器 localhost 实时刷新
dump/batch：文档或子树序列化为可重放 JSON（模板 → N 变体生成）
```

## 3. 与 wpscli 对比

| 维度 | wpscli（WPS 12.1） | OfficeCLI（v1.0.144） |
|------|-------------------|----------------------|
| 定位 | 本地文档格式转换 | Agent-native 文档创建/读取/分析/修改 |
| 安装 | 随 WPS Office 客户端 | 单二进制（33MB），无需 Office |
| 格式 | PDF↔Word/Excel/PPT/MD/TXT/图片 + PDF 页面操作 | docx/xlsx/pptx 全读写 |
| **渲染/截图** | **word2photo/pdf2photo 需 WPS 会员（实测 code 101）** | **view html/screenshot 免费**（实测 38KB PNG） |
| 元数据 | pdfinfo（PDF 页数/扫描） | view stats / view outline |
| 问题分析 | 无 | view issues / validate（结构化错误码） |
| Agent 集成 | wpscli install（Claude Code 等） | MCP Server + skill 自动安装 + JSON |
| JSON 输出 | 支持 | 支持（统一 schema） |

**关键差异**：wpscli 的**渲染截图需会员**（我们实测 CAP-WORD-F 因此受阻）；
OfficeCLI 的 `view screenshot` **免费可用**——恰好补上这个缺口。

## 4. FormulaFix DOCX QA 可用性评估

### 4.1 实测结果（本机 Windows，v1.0.144）

```text
下载：officecli-win-x64.exe（33,382,312 bytes），--version → 1.0.144 ✅
view html：cap_word_f_visual.docx → view_visual.html（62,209 bytes）✅
view screenshot：--page 1 → shot_1.png（38,073 bytes）✅  ← 无会员限制！
```

### 4.2 对 DOCX QA 的价值

| CAP-WORD 项 | 现状 | OfficeCLI 补强 |
|------------|------|---------------|
| CAP-WORD-B WPS Consumer | ✅ wpscli word2pdf | 不变 |
| **CAP-WORD-F Visual** | ⚠️ word2photo 需会员，收口为 PDF 捕获 | **`view screenshot` 免费 → 截图能力补齐（golden=pending_review → 可出 PNG）** |
| CAP-WORD-D Agent Inspection | ✅ ffx export audit | 可加 `view issues` / `validate`（结构化问题分析，L1/L3 层） |
| 公式视觉 | 无渲染时 fallback 文本（BUG-WORD-001 已修） | **view html 渲染公式（OMML→LaTeX KaTeX）→ 视觉保真可验证** |

### 4.3 结论

```text
OfficeCLI 可作为 DOCX QA 的第三消费端（WPS + LibreOffice + OfficeCLI）：
  ✅ view screenshot 免费 → 补 CAP-WORD-F 视觉缺口（wpscli 会员限制的替代）
  ✅ view html 渲染公式 → 补 L6 Visual Fidelity 的公式视觉验证
  ✅ view issues / validate → 结构化问题分析（Agent 可自愈）
  ✅ 单二进制无 Office 依赖 → CI/Docker/headless 可用
  ✅ MCP Server → 与 FFX/ADI/ADL Agent 闭环天然集成

不替代 wpscli：wpscli 仍是主消费端（真实 Office-compatible 引擎，
word2pdf/pdf2txt 已验证）；OfficeCLI 是「渲染/视觉 + Agent 分析」补充。

建议（若推进）：
  1. ffx export audit 增加 officecli 探测（view screenshot 输出 PNG + 
     view issues 结构化问题）
  2. CAP-WORD-F 升级：golden=pending_review → 产出真实 PNG 供 Agent/人工审阅
```

---

## 5. 风险与注意

```text
- 渲染引擎为从零实现（非 Office/WPS 引擎）：视觉保真以 KaTeX/HTML 渲染为
  基线，与真实 Word/WPS 排版有差异 → 视觉结果标注「OfficeCLI 渲染视图」
- 二进制 33MB：CI 需缓存或单独下载步骤
- 开源（GitHub 28.7K star，活跃）：license 需确认（MIT/其他）后再引入
- 公式渲染（OMML→LaTeX）覆盖度需实测验证（复杂公式边界）
```
