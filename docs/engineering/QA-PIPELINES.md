# DOCX QA Pipeline 设计（Agent-native Export QA）

**日期**: 2026-08-18
**前置**: Word Export Product Reliability Audit（L1-L6）+ BUG-WORD-001 修复
**状态**: 设计完成（方案采纳：三级验收 + Agent-native QA 入口）
**关联**: ffx export audit（CAP-WORD-A~G）/ ADI-ADL Agent Engineering Loop

---

## 1. 核心原则

```text
「验证 DOCX」≠「必须安装 Microsoft Word」
```

Word Desktop 是**被测对象（layout engine）**，不是唯一裁判。DOCX 的多数质量
层级可以由 Agent-native inspection + 多消费者验证完成；只有「Word Engine
本身的行为」才需要 Word——那属于 **Release Gate 认证**，不是每次 PR 都必须跑。

## 2. 三级验收标准

### Level A：Agent-native DOCX Quality（默认 CI / Agent QA）

不需要 Microsoft Word：

```text
OOXML / ZIP Structural Validation
Semantic Validation
WPS Consumer（真实 Office-compatible consumer 打开/转换）
PDF conversion + text extraction
Agent DOCX Skill Inspection
```

### Level B：Office-compatible Quality（多引擎兼容 QA）

```text
Level A 全部
+ LibreOffice / 其他 OOXML consumer（多引擎交叉验证）
```

### Level C：Microsoft Word Compatibility（最终兼容性认证）

```text
有 Word 环境时运行：
  Word Desktop → open → no repair prompt → render → screenshot/semantic check
```

属于 **Compatibility Certification / Release Gate**——重要版本才运行。

## 3. CAP-WORD-A~G 验收项

| # | 验收项 | 层级 | 验证内容 | 状态 |
|---|--------|------|---------|------|
| CAP-WORD-A | OOXML Integrity | A | ZIP 解包 + CRC + [Content_Types] + document/styles/settings + rels 无 dangling + **解析器级 well-formed（XmlDocument.parse 全部 XML parts + 嵌套深度 + 属性解码）** | ✅（word_export_zip_integrity_test，8 项含 CAP-WORD-018b） |
| CAP-WORD-B | WPS Consumer | A | WPS 12.1 wpscli 深度验证：word2pdf 转换 + pdfinfo 元数据 + pdf2txt 消费端文本 | ✅（wpscli 实测 + ffx export audit 集成） |
| CAP-WORD-C | LibreOffice Consumer | B | LibreOffice headless 打开/转换（soffice --convert-to pdf；audit 已支持探测，可选二级引擎，本机未装） | ✅（代码已实现，可选） |
| CAP-WORD-D | Agent DOCX Skill Inspection | A | Agent 解包 → XML 校验 → 内容/结构检查 → 报告（ffx export audit） | ✅（已实现，见 §8） |
| CAP-WORD-E | Semantic Fidelity | A | 标题/中文/列表/表格/公式语义保留（extractor + pdf2txt） | ✅（word_export_semantic_fidelity_test，4 项） |
| CAP-WORD-F | Visual PDF/Screenshot | A/B | word2pdf 产物（2 页）+ pdfinfo 元数据 + **officecli view screenshot（真实 PNG，无会员限制）** + view issues（结构化问题） | ✅（PDF 捕获 + officecli PNG + issues 分析；wps word2photo 需会员已由 officecli 替代） |
| CAP-WORD-G | Microsoft Word Desktop | C | Word 打开 + 无 repair + 渲染验证 | ⏳（Release Gate，有 Word 环境才跑；Word 线已冻结，非当前主线） |

### Word 线收口声明（2026-08-19）

```text
Word Export 状态：未知风险 → 受控风险（已收口，冻结深挖）

已闭环（全部 ✅，有真实消费端证据）：
  Artifact Integrity       ✅  OOXML/ZIP/rels 结构
  DOCX Semantic            ✅  标题/列表/表格/公式语义
  WPS Consumer             ✅  wpscli word2pdf 转换成功
  WPS PDF Metadata         ✅  pdfinfo 页数/扫描提示
  WPS Consumer Text        ✅  pdf2txt 消费端文本（公式保真）
  Export Regression        ✅  50 项测试 + CAP-WORD-017 模拟机
  Visual（PDF 捕获）        ✅/Review  word2pdf 2 页 + golden=pending_review

未闭环（非当前主线，后续视需要再评估）：
  Microsoft Word Desktop   UNKNOWN  Release Gate（Level C，有 Word 环境才跑）
  像素级截图                ⏳  word2photo/pdf2photo 需 WPS 会员

冻结决定：Word Export 不再深挖；QA 能力已沉淀为 ffx export audit
（Agent-native，任意文档可跑）。后续优先级转至 Phase 3.9 Behavior Audit。
```

## 4. JSON 质量报告模型
`ffx export audit --format docx` 输出：

```json
{
  "artifact_integrity": "pass",
  "wps_compatibility": "pass",
  "semantic_fidelity": "pass",
  "visual_fidelity": "warn",
  "microsoft_word": "unknown",
  "details": {
    "zip_crc": "pass",
    "content_types": "pass",
    "relationships": "pass",
    "formula_fallback": "pass",
    "dangling_rels": 0
  }
}
```

语义：`pass` / `warn` / `fail` / `unknown`（unknown = 该层未验证，非失败）。

## 5. QA Pipeline 架构

```text
                         FormulaFix
                             ↓
                           .docx
                             │
             ┌───────────────┼────────────────┐
             ↓               ↓                ↓
       OOXML Validator   WPS Consumer     Agent Skill
             │               │                │
             ↓               ↓                ↓
       Structure        Open / Convert    Semantic /
       Relationships    PDF / Render      Layout Review
             │               │                │
             └───────────────┼────────────────┘
                             ↓
                       Quality Report（JSON）
```

## 6. 与 ADI / ADL 的闭环（Agent-native Export QA）

```text
DOCX
 ↓
Inspection（ffx export audit --format docx）
 ↓
Validation Evidence（JSON 报告）
 ↓
Agent
 ↓
发现问题（如 CAP-WORD-008 formula rendered fail）
 ↓
修复 exporter（word_ooxml_builder.dart）
 ↓
重新 export
 ↓
再次验证（QA 回归）
```

未来场景（无需人工告知）：

```text
ffx export audit --format docx
→ CAP-WORD-008 FAIL
  formula semantic structure = pass
  rendered formula = fail
  image relationship = broken
→ Agent 修 word_ooxml_builder.dart → 重跑
```

## 7. 分工总结

```text
Agent Skill（ffx export audit） → 高频自动 QA（默认 CI）
WPS / LibreOffice                → 多引擎兼容 QA（Level B）
Microsoft Word Desktop           → 最终兼容性认证（Release Gate，Level C）
```

**关键收益**：Agent 不应因缺少某个 GUI 软件就无法验证产品能力——大部分
DOCX 质量由 Agent-native inspection + 多消费者验证完成；只有 Word Engine
本身的行为才需要 Word。

---

## 8. 实现：ffx export audit（CAP-WORD-D，2026-08-19 落地）

```bash
ffx --json analyze audit <path.docx>
```

### 8.1 OfficeCLI 集成（CAP-WORD-F 视觉升级，2026-08-19）

docx_qa.py 新增 OfficeCLI（iOfficeAI，Agent-native Office 工具）探测与验证：

```text
_find_officecli()          探测 officecli.exe（PATH / D:/Temp/officecli /
                           LOCALAPPDATA / Program Files）
_officecli_visual_check()  view screenshot --page 1 → PNG（无会员限制，
                           替代 wpscli word2photo 的会员门槛）
_officecli_issues_check()  view issues --json → 结构化问题清单
                           （id/severity/path/message，Agent 可自愈）
```

audit 输出新增：

```json
{
  "visual_fidelity": "review",
  "details": {
    "officecli_visual": {"status": "pass", "png_path": "...page_1.png", "page_count": 1},
    "officecli_issues": {"status": "pass", "issue_count": 14,
      "issues": [{"id": "S1", "severity": 1, "path": "/body/p[3]", "message": "Empty paragraph"}]},
    "visual_note": "officecli view screenshot 已捕获（Agent/人工审阅）"
  }
}
```

**关键收益**：CAP-WORD-F 从「PDF 捕获 + golden=pending_review」升级为
**真实 PNG 截图 + 结构化问题分析**——Agent 可直接读图审阅排版（render →
look → fix 闭环），且 view issues 提供结构化问题供自愈。

Agent-native DOCX QA 命令（tools/ffx-cli/cli_anything/ffx/core/docx_qa.py）：

- **OOXML / ZIP Structural Validation**：ZIP 解包 + CRC + [Content_Types] +
  document/styles/settings 存在性 + rels 无 dangling
- **Semantic Validation**：paragraph/heading/list/table/formula count + 文本预览
- **WPS Consumer**（可选增强）：探测 wpscli.exe（用户级/程序级安装路径），
  存在则 word2pdf 转换作为真实消费端证据

输出 JSON 质量报告（模型见 §4）：

```json
{
  "artifact_integrity": "pass",
  "semantic_fidelity": "pass",
  "wps_compatibility": "pass",
  "visual_fidelity": "unknown",
  "microsoft_word": "unknown",
  "details": {
    "zip_crc": "pass", "content_types": "pass",
    "dangling_rels": [], "relationships": "pass",
    "semantic": {"paragraph_count": 9, "heading_count": 1,
                 "list_count": 2, "table_count": 1, "formula_count": 0,
                 "text_count": 11, "text_preview": "...|E=mc^2|..."},
    "wps": "wps word2pdf ok (wpscli=C:\\...\\wpscli.exe)"
  }
}
```

实测（修复后 docx）：artifact_integrity=pass / semantic_fidelity=pass /
wps_compatibility=pass；边界：非 docx → unsupported format，损坏 zip →
artifact_integrity=fail，文件不存在 → fail。
