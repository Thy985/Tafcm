# 外部项目赋能规划 — 基于 Issue #264

> **来源**：[Tafcm #264 外部可借鉴和参考的项目](https://github.com/Thy985/Tafcm/issues/264)（2026-09-09）
> **范围**：分析 issue 列举的 4 个外部项目 → 对照本仓库代码实况 → 规划分阶段赋能路径
> **第一阶段约束**：只优化**已有功能**，不新增大阶段功能（遵守 AGENTS.md 阶段空档期规则）
> **分析基线**：`feat/firebase-appbar-e2e` @ `8f76f51`（2026-09-11）

---

## 1. Issue #264 外部项目速览

| 项目 | 类型 | 核心亮点 | 对 Tafcm 的参考价值 |
|------|------|---------|-------------------|
| **Markor** | 安卓 Markdown 编辑器（应用级） | 完全离线、多格式、实时预览、代码行号、Mermaid、极简 UI、深浅主题 | 纯本地文件管理、轻量预览渲染、极简交互 |
| **Jota / Jota+** | 移动端文本编辑器（应用级） | 百万字符级大文本、多编码检测/转换、换行符检测、历史版本、正则搜索替换 | 大文件内存优化、编码兜底、持久版本管理 |
| **SoloMD** | 跨平台 Markdown 全家桶（应用级） | 15MB 小包、实时预览、Wiki 链接、本地 RAG 语义搜索、AutoGit 版本历史、零插件集成 | 高集成架构、本地语义搜索、轻量版本控制 |
| **Markwon** | 安卓渲染库（底层） | CommonMark、无 WebView/HTML 中间层、AST → Spannable 直映、高性能低内存 | 渲染管线去 WebView 化的性能天花板参照 |

**一个关键观察**：issue 列举的 4 个项目覆盖了三个层次——
1. **产品形态层**（Markor / Jota / SoloMD）：离线优先、本地文件、极简可靠；
2. **能力层**（搜索 / 版本历史 / 编码兼容 / 大文件）；
3. **技术底座层**（Markwon：原生渲染）。

Tafcm 的差异化定位（公式/图表学术写作 + WYSIWYG）不需要照抄任何一家，但每一层的**工程实践**都可以直接赋能。

---

## 2. 本项目现状盘点（代码证据）

> 以下结论均来自 2026-09-11 对 `flutter_app/lib` 的实读，非文档转述。

### 2.1 渲染管线（对照 Markwon）

| 环节 | 现状 | 证据 |
|------|------|------|
| Block 编辑/渲染 | ✅ 原生 Flutter widget（WYSIWYG），不走 WebView | `presentation/blocks/*`（paragraph/heading/code/table/formula/mermaid 各 block 独立实现） |
| Markdown 解析 | ✅ 自研 parser，AST 驱动 | `core/parser/markdown_parser.dart` |
| **公式（LaTeX）** | ⚠️ 离屏 WebView + MathJax → SVG；超时降级 PNG/文本 | `core/services/formula_svg_service.dart`（共享 MermaidService 的 WebView，32MB 缓存、连续超时 3 次重置） |
| **Mermaid 图表** | ⚠️ 离屏 WebView + mermaid.min.js（本地资产，100% 离线） | `core/services/mermaid_service.dart` |
| PDF 导出 | ✅ 纯 Dart（`pw.SvgImage` 矢量嵌入） | `domain/exporters/pdf_exporter.dart` / `formula_pdf_renderer.dart` |

**结论**：正文渲染已是"Markwon 式"原生直映，**只有公式/图表依赖 WebView**。Markwon 的参考意义不在"迁移渲染库"，而在：a) 提醒我们 WebView 是性能/稳定性最脆弱的一环（历史上已有超时级联、页面未就绪等专项修复）；b) 其"语法树→原生组件直映"思路可用于评估未来 inline 公式的原生渲染方案。

### 2.2 文件管理与存储（对照 Markor / Jota）

| 能力 | 现状 | 证据 |
|------|------|------|
| .md 单一真相源 | ✅ 已落地 ADR-0003 | `core/document_repository.dart`（端口）+ `core/services/file_repository.dart`（实现） |
| 编码兜底 | ✅ BOM → 严格 UTF-8 → 容错 UTF-8 → GB18030 → Latin-1 | `core/services/file_service.dart:13-41` `decodeBytesAuto` |
| 外部打开（ACTION_VIEW） | ✅ 微信/QQ/浏览器 → 本应用 | `core/services/external_file_service.dart`（冷/热启动 URI 均覆盖） |
| 文件列表元数据 | ✅ `DocMetadata` 不加载正文，避免大文件全量读 | `core/services/file_repository.dart:12-15` |
| 文件树面板 | ✅ 已有 | `presentation/panels/file_tree_panel.dart` |
| **手动编码指定/转换** | ❌ 无。`decodeBytesAuto` 是黑盒，用户无法强制 GBK | `file_service.dart` |
| **换行符检测/归一** | ⚠️ 未见 CRLF/LF 检测逻辑（grep 无 `line-ending`/`crlf` 相关实现） | — |

### 2.3 搜索与版本（对照 Jota / SoloMD）

| 能力 | 现状 | 证据 |
|------|------|------|
| 文档级搜索（标题/内容） | ⚠️ **后端已实现、前端未接线** | `file_repository.dart:254` `searchDocuments(query)` 存在；但 `home_screen.dart:169-173` `_onSearch` 只弹 "搜索即将上线" SnackBar |
| 编辑器内查找/替换 | ❌ 无（正则搜索替换是 Jota 强项） | — |
| Undo/Redo | ✅ Transaction 级 op-delta 模型，栈深 50 | `core/utils/history_manager.dart` + `core/editing/editor_history.dart` |
| **持久版本历史/快照** | ❌ 无。undo 栈是会话内存态，退出即失 | — |
| 自动保存 | ✅ 已有 | `presentation/editor/autosave_service.dart` |
| 本地 RAG / 语义搜索 | ❌ 无（SoloMD 特色，列为远期） | — |

### 2.4 大文件处理（对照 Jota）

| 能力 | 现状 | 证据 |
|------|------|------|
| 列表页防全量加载 | ✅ DocMetadata | `file_repository.dart` |
| **编辑器大文件策略** | ❌ 无分页/虚拟化。全文一次载入 AST + 全 block 渲染 | `core/editing/document_editor.dart`（无懒加载分节） |
| 外部读取时序 | ✅ 按需读取（EditorPage 触发），避免启动卡顿 | `external_file_service.dart:17-20` 设计权衡注释 |

---

## 3. 赋能总体规划：三个阶段

```
第一阶段（本文件重点）        第二阶段                    第三阶段
"优化已有功能"               "补齐能力缺口"              "底座升级"
────────────────────        ────────────────────       ────────────────────
搜索接线（后端已有）          编辑器内查找/替换            公式/图表去 WebView 评估
文件树/列表体验打磨          持久版本历史（快照）          inline 公式原生渲染
编码手动指定 + 转换          大文件渐进加载               本地语义搜索（RAG）
大文件防御性保护             换行符检测与归一             Wiki 链接（SoloMD）
WebView 稳定性加固          正则搜索替换
```

**排序原则**：
1. 第一阶段全部是**已有功能的接线/加固**，无新架构、无 ADR 负担、不动渲染模型——符合阶段空档期约束；
2. 第二阶段引入持久化/渐进加载，涉及 ADR（存储边界、编辑模型），需 Human Owner 立项；
3. 第三阶段动技术底座（渲染管线、语义索引），必须先落 ADR 再实施。

---

## 4. 第一阶段：优化已有功能（详细规划）

> 目标：把"后端已有但用户用不到"和"已有但不够稳"的功能补到位。
> 每项给出：参考来源 → 现状 → 方案 → 验收标准 → 工作量估计（人日，含测试）。

### 4.1 P0-1 全局搜索接线 ⭐ 最高性价比

- **参考来源**：Markor（本地文件全文搜索，无需索引即可用）；SoloMD（搜索是核心入口）
- **现状**：`FileRepository.searchDocuments()` 已实现（`file_repository.dart:254`），`HomeScreen._onSearch` 只弹"搜索即将上线"；`SearchPill` 组件也已在 `buttons.dart:184` 就绪但未接入
- **方案**：
  1. 首页搜索按钮 → push `/search` 路由（新屏，复用 `SearchPill` + `DocMetadata` 列表项样式）
  2. 输入防抖 300ms → 调 `searchDocuments` → 高亮命中片段（复用 `getDocumentPreview` 的截取逻辑）
  3. 命中项点击 → `context.go('/editor?path=...')`（与首页卡片同路径）
  4. 搜索范围开关：仅标题 / 标题+正文（后端已支持两种粒度）
- **验收**：widget 测试覆盖搜索屏三态（loading/empty/results）；中文关键词命中；结果点击进编辑器
- **工作量**：2-3 人日
- **风险**：低——纯 presentation 层接线，不动 domain

### 4.2 P0-2 编码手动指定与转换（编码兜底的"显式化"）

- **参考来源**：Jota 的多字符编码检测/转换是核心卖点；本项目 `decodeBytesAuto` 已是自动黑盒
- **现状**：自动解码链已很完善（BOM/UTF-8/GB18030/Latin-1），但两点缺失：
  a) 自动判定失败（乱码）时用户无救济手段；
  b) 保存时写回原编码不可控（`saveToFile` / `writeDocument` 固定 UTF-8，GBK 原件经打开→保存会变成 UTF-8，用户可能不希望）
- **方案**：
  1. 导入/打开文件时若检出 U+FFFD（容错解码痕迹），在编辑器顶栏显示"编码异常"提示条 → 点击弹出编码选择（UTF-8 / GB18030 / Big5 / Latin-1），重新解码
  2. `loadFromPath` 增加 `encoding` 可选参数，绕过自动链
  3. 保存路径：暂不改默认 UTF-8（ADR-0003 目标态），但在文档 front-matter 支持 `encoding: gb18030` 声明（读端尊重声明，写端按声明写回）——这是最小侵入的兼容方案
- **验收**：GBK 文件打开 → 手动切 GB18030 → 中文正常；带 front-matter 声明的文件保存后字节仍为 GBK
- **工作量**：3-4 人日
- **依赖**：需在 `decodeBytesAuto` 旁新增 `decodeBytesWith(bytes, encoding)`（同文件，不新增第四套存储）

### 4.3 P1-3 大文件防御性保护

- **参考来源**：Jota 的百万字符编辑能力（我们不做到百万，但要做"不崩"）
- **现状**：编辑器全文载入 AST + 全 block 渲染，无任何体积阈值保护。用户从微信打开一个 10MB 日志型 .md → 解析卡死 → 崩溃或 OOM
- **方案**（防御为主，不实现分页）：
  1. 打开文件时统计字节数：> 2MB 弹确认对话框（"该文件较大，渲染可能卡顿，仍要打开？"）
  2. > 8MB 建议以"只读预览"模式打开（复用现有 preview 路径，跳过 WYSIWYG block 构建）
  3. AST 解析增加输入长度熔断：超阈值时按段落切块解析，失败段落降级为纯文本块（parser 已有单行错误回调 `MarkdownParseErrorHandler`，扩展为块级即可）
- **验收**：构造 5MB / 12MB 测试文件，打开不崩溃、有明确提示；现有全部测试不回归
- **工作量**：2-3 人日
- **说明**：真正的渐进加载/虚拟化留第二阶段（动 DocumentEditor，需 ADR）

### 4.4 P1-4 WebView 渲染稳定性加固（Markwon 反向启示）

- **参考来源**：Markwon 的存在本身证明了"无 WebView 渲染"是性能天花板；在到达之前，先让 WebView 路径足够稳
- **现状**：`formula_svg_service.dart` / `mermaid_service.dart` 已有多轮专项修复（协议 v2、连续超时 3 次才重置、页面未就绪快速降级），但重置路径仍会清空整批请求
- **方案**：
  1. 渲染请求持久化去重缓存落盘（当前 `_maxCacheBytes` 32MB 内存缓存，冷启动即失）——SVG 结果写应用缓存目录，key 已有 hash（`crypto` 已依赖）
  2. WebView 重置后自动重放失败批次（当前语义是"清空等待队列"，改为 reset 完成后按原序重试一次）
  3. 增加渲染耗时指标到 ADI（`render_tracer.dart` 已有采集面）——为第三阶段"去 WebView 评估"积累数据
- **验收**：杀进程重开文档，公式/图表首屏命中率显著提升（手动验证 + ADI 数据）；连续超时场景不再丢失整批
- **工作量**：3-4 人日
- **风险**：中——涉及 MermaidService 共享 WebView 契约，需回归公式/图表全部测试

### 4.5 P2-5 文件列表体验对齐 Markor

- **参考来源**：Markor 的极简本地文件管理（排序、最近、批量操作）
- **现状**：首页"最近 3 篇 + 更早"已实现；文件树面板已有；但列表无排序切换（仅 modified 降序）、无多选批量删除/移动
- **方案**：
  1. 列表排序切换：修改时间 / 标题（`listDocuments` 已有 sort 逻辑，加参数即可）
  2. 长按进入多选模式 → 批量删除（复用 `deleteDocument`，二次确认）
- **验收**：widget 测试排序切换 + 多选删除流程
- **工作量**：2 人日

### 4.6 第一阶段汇总与排期

| 项 | 优先级 | 工作量 | 主要触及层 | 是否需 ADR |
|----|-------|--------|-----------|-----------|
| 4.1 搜索接线 | P0 | 2-3 人日 | presentation | 否 |
| 4.2 编码显式化 | P0 | 3-4 人日 | core/services + 少量 UI | 否（front-matter 约定需在 docs 登记） |
| 4.3 大文件保护 | P1 | 2-3 人日 | editor + parser | 否（熔断不改架构） |
| 4.4 WebView 加固 | P1 | 3-4 人日 | core/services | 否 |
| 4.5 列表体验 | P2 | 2 人日 | presentation | 否 |

合计 12-16 人日。每项独立成 PR（feat/fix 分支），遵守 §5.3 检查清单；4.4 建议最后做（回归面最大）。

---

## 5. 第二阶段预告（简述，立项时再展开）

| 方向 | 参考来源 | 关键点 | 前置 |
|------|---------|--------|------|
| 持久版本历史 | Jota 文件历史 / SoloMD AutoGit | 基于已有 autosave 挂钩，保存时落快照到 `.tafcm/history/`（或 git 轻量封装）；ADR-0003 边界内评估 | 需 ADR（存储边界扩展） |
| 编辑器内查找/替换 | Jota 正则搜索替换 | Block 模型上做跨块查找（BlockId 定位 → transaction 替换），天然支持 undo | 无 |
| 换行符检测归一 | Jota | 读端检测 CRLF → 统一 LF 编辑 → 写端保留原风格 | 无 |
| 大文件渐进加载 | Jota 分页 | DocumentEditor 按章节懒解析 + ListView 虚拟化 | 需 ADR（编辑模型） |

## 6. 第三阶段预告（简述）

- **公式/图表去 WebView**（Markwon 精神）：以 4.4 积累的 ADI 耗时数据为依据，评估纯 Dart LaTeX→SVG 方案（如 flutter_math_fork 类库）替代 MathJax 路径；目标是首屏公式零 WebView 等待
- **本地语义搜索**（SoloMD）：文档 embedding + 本地向量检索；仅在 4.1 的关键词搜索被证明不够用后立项
- **Wiki 链接**（SoloMD）：`[[链接]]` 语法 + 文件间跳转，依赖文件树已稳定

---

## 7. 与治理规则的符合性自查

- ✅ 第一阶段不启动新大阶段功能（全部是已有功能接线/加固）
- ✅ 不新增第四套存储（4.2 声明式编码走 front-matter，4.4 缓存走应用 cache 目录非文档存储）
- ✅ 不动 UI Prototype 相关历史结论（Phase 3 UI 已完成，本次为既有 UI 内的功能补全）
- ✅ 架构决策留待 ADR（二/三阶段项均标注前置 ADR）
- ✅ 每项有测试验收标准，遵守 §9.1 "写测试"要求

---

## 8. 诚实差距分析：我们的"已实现"达到外部项目成熟度了吗？

> **追问**：§2 盘点只回答了"有没有"，本节回答"好不好"。对照外部项目逐一给成熟度评级。
> 评级口径：★☆☆（占位/雏形）｜★★☆（可用但有明显短板）｜★★★（成熟，可对标外部项目）
> **结论先行**：核心编辑管线（解析/undo/autosave/WYSIWYG）成熟度不低于外部项目，个别面（autosave、编码兜底）**工程深度超过** Markor/SoloMD；但**产品完整度**整体落后一个身位——多数功能是"骨架级可用"，缺打磨层。

### 8.1 逐项成熟度对比

| 能力 | Tafcm 实况（代码实证） | 评级 | 外部参照 | 差距本质 |
|------|----------------------|------|---------|---------|
| 自动保存 | `autosave_service.dart`：debounce + 并发串行化 + 指数退避重试 + 状态机（idle/saving/saved/error/retrying）+ 失败进诊断 | **★★★ 超出参照** | Markor（保存时机简单）/ SoloMD 未见更细 | 无差距，**设计深度领先**（ADR-0013） |
| 编码兜底 | `decodeBytesAuto` 五级链 | **★★☆** | Jota：手动选编码+编码转换 | 自动链不差，但**无用户救济手段**（见 4.2） |
| 文件监听 | `watchAllDocuments`：目录 watch + 断线退避重连 | **★★★** | Markor 同级 | 持平 |
| 全局搜索 | `searchDocuments`：全量读入→小写 contains | **★☆☆ 实现级** | Markor：搜索+高亮+范围 | **后端只是最朴素实现**：每次搜索全量读所有文件正文（`_readAll` 含 content），无增量、无高亮、无结果排序。接线上去后体验会明显弱于 Markor，**需同步优化查询路径** |
| 文档列表 | DocMetadata + 监听 + 预览片段 | **★★☆** | Markor：文件夹树/排序/批量操作 | 缺排序切换、批量操作、文件夹层级（我们只有单一 documents 目录**拍平**） |
| 版本历史 | 无（undo 栈内存态） | **☆☆☆** | Jota 文件历史 / SoloMD AutoGit | 完全缺失 |
| 公式渲染 | MathJax→SVG+PNG 回退+缓存+超时降级 | **★★★ 差异化** | 四项目均无此能力 | 领先但依赖 WebView（§4.4） |
| Mermaid | 同上 | **★★★** | Markor 有（同为 WebView） | 持平 Markor，工程细节（协议v2/级联保护）更细 |
| 表格编辑 | 渲染+源码 TextField 双态 | **★☆☆** | Typora 可视化编辑；Markor 源码级 | 介于两者，距 Typora 差距大（GAP #8） |
| 导出 | PDF/Word/TXT | **★★☆** | Typora 7 种 | 广度不足，但 Word/PDF 有消费端验证（RUN-011），质量高于"能导出" |
| 主题 | 3 套 token 驱动 | **★★☆** | Markor 深/浅 | 数量少但 token 体系规范；代码高亮不随主题（DEBT-011） |
| 大文件 | 无防护 | **☆☆☆** | Jota 百万字符 | 完全缺失 |

### 8.2 与四个外部项目的一对一结论

- **vs Markor**：Markor 是"功能不多但每件都打磨完"的典型——搜索即搜即得、文件夹层级、批量操作全是完成态。Tafcm 的**编辑内核比它深**（Transaction/undo/autosave/公式），但**文件管理面比它浅**。补齐 §4.1/4.5 后文件管理面才到 Markor 的 80%。
- **vs Jota**：Jota 的护城河是大文件与编码。Tafcm 编码自动链已对齐其自动检测部分，**手动编码/转换（4.2）与大文件（4.3）是硬缺口**——不补这两项，Jota 类用户（中文/大文档场景）会直接流失。
- **vs SoloMD**：集成都度高（搜索/版本/链接全家桶）。Tafcm 单项能力多不输，但**"全家桶"整合度低**——搜索没接线就是零。差距不在单点技术，在**产品完成度**。
- **vs Markwon**：不可比（库 vs 应用）。真正的启示在 §2.1：正文渲染我们已是同类思路，公式/Mermaid 的 WebView 是唯一没走通"原生直映"的环节。

### 8.3 对第一阶段规划的修正（基于本节发现）

1. **4.1 搜索接线升级为"接线+查询路径优化"**：`searchDocuments` 全量读正文的实现在文档数上百后会卡，需改为 DocMetadata 级过滤（标题优先）+ 按需读正文，工作量 2-3 → 3-4 人日。
2. **4.2 编码显式化优先级维持 P0**——Jota 对比确认这是中文用户的硬缺口。
3. **新增认知**：autosave/undo/文件监听不需要"优化"，已是资产。第一阶段精力应全部投在 §4.1-4.5，不要回头打磨已 ★★★ 的部分。

### 8.4 一句话总评

> Tafcm 的**底座工程质量**（架构分层、事务化编辑、可观测、ADR 治理）高于全部四个参照项目；**用户可感知的产品成熟度**（搜索/文件管理/版本/大文件）低于 Markor 和 Jota。第一阶段规划的本质就是：把底座优势兑换成产品完整度。

---

## 9. 专项差距分析：Markdown 解析与渲染

> **追问**：自研 parser/renderer 与外部成熟实现（Markwon / markdown-it / Markor ViewModel / Typora）的真实差距。
> 依据：`markdown_parser.dart`（507 行）/ `block_serializer.dart`（294 行）/ `block_renderer.dart` / `inline_spans.dart` / `formula_extractor.dart`（277 行）全文实读 + test/parser 测试盘点。

### 9.1 语法覆盖面：约 60-70% 常用语法，非 CommonMark 兼容

**已支持**（块级 10 类 + 行内 8 类）：
fenced code（含 mermaid 特判/空块保真）、ATX 标题、无序/有序列表 + 缩进嵌套树（ADR-0029）、任务列表、引用、GFM 管道表格、分割线、段落合并（保 hard-break `\n`）；行内：图片/链接/行内代码/加粗/斜体（`*` 与受限 `_`）/删除线/**公式**。

**不支持**（对照 CommonMark + GFM，按日常碰到的概率排序）：

| 缺失语法 | 影响 | 外部对照 |
|----------|------|---------|
| 引用块多行/嵌套（`> >`、lazy continuation） | 主 parser 逐行独立成块，`> a\n> b` 变两个 QuoteBlock；嵌套引用整块降级为文本 | Markwon/markdown-it/Typora 全支持 |
| 缩进代码块（4 空格） | **静默损坏**：`_parseInline` `trimLeft()` 吃掉缩进 → 内容变普通段落，round-trip 不可逆 | CommonMark 核心 |
| 有序列表起始编号 | `ListElement` 不存 start，序列化恒写 `1. ` → `3. a` round-trip 后变 `1. a` | CommonMark 核心 |
| 表格对齐（`:` 分隔行） | separator 行被跳过，`TableElement` 无 alignment 字段 → 对齐信息**丢失** | GFM |
| 链接引用定义 `[ref]: url` | 不识别，整行变段落文本 | CommonMark 核心 |
| 自动链接 `<url>` / 裸 URL（GFM autolink） | 不识别 | GFM |
| 反斜杠转义 `\*` `\_` | inline 扫描不跳过转义 → `\*x\*` 仍解析出斜体 | CommonMark 核心 |
| 多反引号 code span（``a ` b``） | 单反引号正则不匹配 | CommonMark 核心 |
| Setext 标题（`===`/`---` 下划线） | `---` 会误判为分割线 | CommonMark 核心 |
| HTML 块/行内 HTML、实体引用 `&amp;` | 原样输出文本 | 全部 |
| 脚注/定义列表 | 原样输出（GAP #18 已知） | 扩展 |

**独有能力（外部全没有）**：`FormulaExtractor` 显式（`$`/`$$`）+ **隐式 LaTeX 命令启发式提取**（约 150 个命令白名单）——这是 Typora/Markwon/Markor 都没有的移动端特性，是差异化主轴，但启发式也带来误判风险（有专项 audit 测试守护）。

### 9.2 渲染层差距（block_renderer / inline_spans）

| 项 | Tafcm 实况 | 外部对照 | 差距 |
|----|-----------|---------|------|
| 块级渲染架构 | 10 类 exhaustive switch、无 fallback、专用 Widget（ADR-0022 失败策略） | Markwon：AST→Spannable 直映 | **架构同级甚至更严谨**（编译期穷尽性保障） |
| **链接可点击性** | `inline_spans.dart:73` 只析构 `text`（url 被丢弃），纯样式下划线，**不可点击** | 任何编辑器链接都可点开 | **真实缺陷**，非缺失特性 |
| 网络图片 | 非本地文件路径 → 占位文本 `[图片]`（`_buildImageInline` 只走 `Image.file`） | Markwon/Typora 渲染网络图 | **真实缺陷**：网上复制的文档打开即"图丢失" |
| 代码高亮 | 2 主题、无行号、不随主题切换（DEBT-011） | Markor：行号显示 | 部分差距 |
| 公式行内渲染 | `WidgetSpan` 内嵌 FormulaRenderer，Typora 化样式 | 无参照 | **领先** |
| HTML 渲染 | 完全无 | Markwon 有 HtmlPlugin | 与定位相关性低 |

### 9.3 保真度工程：反超外部应用级项目

这是自研 parser 最强的部分，多数外部应用（含 Markor）没有做到：

- **round-trip fuzz**（`roundtrip_fuzz_test.dart` + fuzz 2001 轮锁死 BUG-1~6）+ edge_case 23 用例 + serializer 11 用例；
- **已知边界显式文档化**（`block_serializer.dart:11-15` 列出 4 类不保真场景），而非假装无损；
- **单行错误降级**（B-5：坏行 → 段落，文档不再打不开）；
- CRLF、尾部空格、空代码块等 round-trip 细节均有 fuzz 来源的修复注释。

### 9.4 结论与建议

> **定位判断**：自研 parser 的目标是"移动端公式写作的 AST 单一真相源"（ADR-0020/0004），不是 CommonMark 兼容渲染库。**不应整体替换为 Markwon/markdown-it**（会失去公式提取、round-trip 资产和 Block 编辑模型对接）；差距应按"最高频缺失优先"渐进补齐。

| 优先级 | 项 | 理由 | 归属 |
|-------|----|------|------|
| P0 | 链接可点击（url-launcher + tap handler） | 现有实现是缺陷不是特性 | 第一阶段（1 人日） |
| P0 | 网络图片渲染（cached_network_image 或占位升级） | "任意来源 .md 即开即看"定位直接受损 | 第一阶段（1-2 人日） |
| P1 | 引用块多行合并 + 嵌套 | 中文笔记高频；主 parser 逐行独立是语义错误 | 第一阶段补解析（2 人日） |
| P1 | 有序列表起始编号 + 表格对齐字段 | round-trip 静默改写用户内容，违反保真原则 | 第一阶段（2 人日） |
| P2 | 反斜杠转义 / 多反引号 code span / autolink | CommonMark 高频边角 | 第二阶段 |
| P2 | 缩进代码块识别 | 4 空格歧义与列表缩进冲突，需 ADR-0004 修订 | 第二阶段 |
| P3 | 跑一遍 CommonMark spec 645 例建立兼容率基线 | 把"约 60-70%"变成精确数字 | 第二阶段 |

---

## 10. 专项差距分析：Block 块的编辑体验

> **追问**：Block 化 WYSIWYG 的实际编辑手感与 Typora / 移动端标杆（Notion、Bear、Obsidian mobile）的差距。
> 依据：`editor_shell.dart` / `live_editing_state.dart` / `input_handler.dart` / `auto_pair_rules.dart` / `auto_continue_rules.dart` / `block_behavior_resolver.dart` / `block_selection.dart` / `block_drag_handle.dart` / `block_reorder.dart` 全文实读。

### 10.1 已做对的部分（先说资产）

| 项 | 实证 | 评价 |
|----|------|------|
| 双状态模型 | live（高频）与 committed（事务）分离，`live_editing_state.dart` | 架构正确，输入不打 undo 栈，Notion 同思路 |
| 回车语义 | 空块 Enter=分块、标题不分多行、Code 块内换行（`block_behavior_resolver.dart:63-110`） | Typora 语义，正确 |
| 自动续列表 | checkbox→有序(编号+1)→引用→无序 优先级匹配 + 空项回车退出（`auto_continue_rules.dart`） | 达到主流编辑器水准 |
| 单步 Undo | 配对/续行合并为单 Command（`input_handler.dart:24-30` 注释记录了原因） | 优于两步 undo 的 naive 实现 |
| 拖拽重排 | ReorderableListView + 纯函数索引换算（`block_reorder.dart`） | 基础可用 |

### 10.2 体验问题清单（按严重度排序）

#### A 级：日常打字就能碰到

| # | 问题 | 代码证据 | 标杆对照 |
|---|------|---------|---------|
| A1 | **非空列表/引用回车不分块也不续行**：`resolveEnter` 对 listItem/blockquote 非空回车只 `InsertTextCommand('\n')`，后续行无前缀；自动续行依赖 IME 提交 `\n` 结尾的 onChanged（`auto_continue_rules.dart:81`），而**硬键盘/部分输入法走 Intent 路径不走 onChanged** → 同一动作两条路径行为不一致：有的场景续行、有的场景裸换行 | `block_behavior_resolver.dart:92-104` + `input_handler.dart` 仅挂在 onChanged | Typora：回车必然续行；Notion：回车必然新块。**没有一条路径是"约定语义"，是两条半成品路径** |
| A2 | **块首退格只合并不退出标记**：列表项块首 Backspace 直接 `MergeWithPreviousCommand`，不是"先去掉 `- ` 前缀变段落，再退格才合并"（代码注释自认 Phase B 未做） | `block_behavior_resolver.dart:120-125` | Typora/Notion：退格先降级块类型，第二次才合并。当前行为一次退格破坏列表结构 |
| A3 | **无跨块选区/多块删除**：选区被块边界切断，无跨块 shift/长按选择、无多选删除 | 全链无 cross-block selection 实现 | 任何编辑器的基础能力 |
| A4 | **光标跨块导航缺失**：块尾→下一块、块首→上一块的方向键/滚动跟随未见实现（`_jumpToBlock` 只服务 TOC） | `editor_shell.dart:181-194` | 打字到块尾继续打字，光标不会自然进入下一块 |

#### B 级：交互打磨缺失

| # | 问题 | 代码证据 | 标杆对照 |
|---|------|---------|---------|
| B1 | **自动配对无选区包裹**：有选区时输 `(` 不包裹选区（注释"留 Phase 3.4+"），且配对符仅 4 种，无 `"` `'` `*` `$` | `auto_pair_rules.dart:11-15,55` | Typora 支持选区包裹与引号配对 |
| B2 | **长按工具条与系统文本选择冲突**：自实现 `Listener.onPointerDown` + 500ms Timer 触发块工具条，未与 Flutter 原生 long-press 选择手势互斥 → 长按选词与块工具条可能同时触发 | `block_selection.dart:83-96` | Notion mobile：长按=块级菜单，再拖=选文本，手势分层明确 |
| B3 | **拖拽手柄常驻占 24px 宽**：左侧固定 24px 手柄列挤压正文（移动端 375px 屏损失 6.4%），且拖拽与 TextField 文本选择手势竞争 | `block_selection.dart:106-113` | Notion：手柄悬浮淡入，不占布局宽度 |
| B4 | **缩放范围与手势冲突**：双指缩放绑定在编辑区 GestureDetector（0.8-1.25 倍），与系统/WebView 内的页面缩放语义不一致，且 clamp 后无溢出反馈 | `editor_shell.dart:289-298` | 移动端标杆多用系统缩放或明确 pinch-to-zoom |
| B5 | **表格单元格仍为源码 TextField**（GAP #8 已知，此处不重复展开） | — | Typora 可视化编辑 |

#### C 级：长文档/性能向

| # | 问题 | 代码证据 | 影响 |
|---|------|---------|------|
| C1 | `isDirty` 每次按键 O(n) 全块遍历比较（注释已自认，预留优化方案） | `live_editing_state.dart:54-67` | 大文档打字掉帧 |
| C2 | 全块常驻渲染，无虚拟化（`Workspace` 列表全量构建）+ `_blockKeys` 只增不减 | `editor_shell.dart:122` | 千块文档内存与首帧劣化 |
| C3 | 每块独立 `ListenableBuilder(coordinator)`，任一状态变化全列表 rebuild | `block_selection.dart:97-99` | 与 C1/C2 叠加放大 |

### 10.3 结论

> Block 模型的**架构资产是真的**（双状态/事务/集中裁决），但**手感层是"Phase A 退化态"**：A1/A2 是行为矩阵里明确标注 Phase B 未做的半成品，A3/A4 是标杆编辑器的地基能力。体验问题集中在**块边界处的行为**（回车/退格/选择/导航）——这正是 Block 化编辑器最难也最显功力的部分。建议 Block 体验专项与 §9 P0 渲染缺陷修复合并立项，A1/A2 属"补齐既定设计"（Phase B）而非新特性。

---

## 11. 可直接拿来用 / 有借鉴意义的清单（综合 issues + 文档调查）

> **输入**：§8 成熟度对比、§9 解析渲染差距、§10 Block 体验问题 + 仓库 open issues（#243-#250、#263-#266，2026-09-11 抓取）+ 参考项目调研。
> **许可证核实**：Markor 代码 **Apache 2.0**（翻译文件 CC0）；Markwon **Apache 2.0**——两者算法/代码均可合规移植（保留版权声明）。Jota（GPL 系）与 SoloMD 未核实到明确宽松许可，**只借设计不搬代码**。

### 11.1 A 级：可直接拿来用（合规移植/直接集成）

| # | 项 | 来源 | 许可 | 对接点（我们的 issue/文档发现） | 形态 |
|---|----|------|------|------------------------------|------|
| A1 | **commonmark-java 解析器作为"参照实现"** | Markwon 底座 | Apache 2.0 | §9 语法覆盖 60-70%、缺转义/多行引用/起始编号——用它的 AST 输出做我们 parser 的**对拍 oracle**（spike_ab_comparison_test 已有 A/B 框架），逐语法补齐，不替换自研 parser | 测试基建 |
| A2 | **Markwon 的节点→Span 映射策略** | Markwon core | Apache 2.0 | §9.2 渲染层：`inline_spans.dart` 只析构 text 丢 url、无 link tap——参考其 `LinkResolver` 模式给 LinkElement 补 tap 处理（url_launcher） | 算法参考 |
| A3 | **Markor 的文件浏览/列表交互范式** | Markor（Java） | Apache 2.0 | §8 文档列表 ★★☆：排序切换、多选批量操作、目录层级。其 `FileChooser` / 列表 ViewModel 的交互状态机可直接照抄结构 | 交互范式 |
| A4 | **常用正则/编码探测表** | Markor 附带工具类 | Apache 2.0 | 4.2 编码显式化：Markor 对 GBK/Big5 的文件名/内容探测辅助逻辑可移植到 `decodeBytesWith` | 工具代码 |

### 11.2 B 级：借鉴设计（不搬代码，照行为/架构做）

| # | 项 | 来源 | 对接点 | 借鉴什么 |
|---|----|------|--------|---------|
| B1 | **回车/退格行为矩阵** | Typora（§10 A1/A2） | `block_behavior_resolver.dart` Phase B 未完成项 | 退格先降级块类型再合并；回车续行走 Intent 路径与 IME 路径同语义——行为规格已写在 §10.2，照表实现 |
| B2 | **autosave 增量写盘** | Jota 文件历史思路 | **issue #249**（autosave 整读整写 IO 尖峰） | 保存时只写变更块重组的文档 + 原子替换；Jota 的"内存态+定时刷盘"分层可借 |
| B3 | **大文件分页/渐进加载** | Jota | §8 大文件 ☆☆☆、§10 C2 无虚拟化 | 打开时先解析首屏 N 块，滚动到边缘再解析后续（parser 已按行流式，天然支持分段） |
| B4 | **编辑内核 O(1) 化** | （内部 issue 对照） | **issue #245**（按键 O(n²) wordCount 序列化）/ **#247**（List 线性扫描）/ **#246**（整树重建）/ §10 C1-C3 | 不来自外部项目，但与 Jota"百万字符不卡"目标对齐：脏块集合增量维护 + Map<BlockId> 索引 + per-block listener 局部刷新。**#245 是唯一 P1，应最优先** |
| B5 | **Wiki 链接 `[[...]]`** | SoloMD | §6 第三阶段预告 | parser 增加一种 inline 类型 + 文件树跳转，SoloMD 证明了移动端单包可行 |
| B6 | **导出并发与超时** | （Markor 无此问题：不重渲染） | **issue #248**（导出无超时）/ **#250**（`_maxConcurrent=4` 无效串行） | 参照我们 legacy 路径的 120s 超时补齐新路径；并发用真实 worker pool——这是修自己的 bug，不借外部 |
| B7 | **本地语义搜索的落地形态** | SoloMD 本地 RAG | §6 第三阶段 | 先落 4.1 关键词搜索（含 §8.3 查询路径优化），语义层后置；SoloMD 的"内置不依赖插件"原则值得守住 |

### 11.3 C 级：明确不建议

| 项 | 理由 |
|----|------|
| 整体替换 parser 为 Markwon/commonmark-java | 会失去公式启发式提取、round-trip fuzz 资产、Block 编辑模型对接（§9.4 已论证） |
| 抄 Markor 的 WebView 预览双模式 | 我们已是真 WYSIWYG，倒退 |
| Jota 代码级移植 | 许可证不明（GPL 系风险），且其 Swing/Android 文本栈与 Flutter 不兼容；只借 B2/B3 设计 |
| SoloMD 的 AutoGit 版本历史 | git 依赖过重，移动端打包体积/维护成本高；第二阶段版本历史用轻量快照方案（§5） |
| 云同步（issues #244） | 四个参考项目全部离线优先且成功——反证当前阶段不该碰云，维持 ADR-0003 本地单一真相源 |

### 11.4 与 open issues 的对账表

| Issue | 内容 | 本文对应 | 建议处置 |
|-------|------|---------|---------|
| #245 (P1) | 按键 O(n²) 全文档序列化 | §10 C1-C3 / B4 | 性能专项第一优先，B4 方案 |
| #246 | notifyListeners 整树重建 | §10 C3 | 同上 |
| #247 | 内核 List 线性扫描 | §10 C2 | 同上（Map 索引） |
| #248 | 导出无全局超时 | §11.2 B6 | 小修复，随导出专项 |
| #249 | autosave 全量 IO | §11.2 B2 | autosave 专项 |
| #250 | 导出串行渲染 | §11.2 B6 | 同 #248 |
| #243/244 | 定位分裂 / 云同步 | §11.3 | Human Owner 决策项，不自动行动 |
| #265/266 | Provider 重复定义 / 守门失效 | AGENTS.md §3.2 已知 | 独立 P2 修复，不属本文档主线 |

### 11.5 执行顺序建议（合并 §4/§9/§10/§11）

1. **第一梯队（1-2 周）**：#245 性能修复（B4）→ §9 P0 链接可点击 + 网络图片 → 4.1 搜索接线
2. **第二梯队**：§10 A1/A2 回车/退格 Phase B → 4.2 编码显式化 → A1 commonmark 对拍基建
3. **第三梯队**：4.3 大文件防护（B3）→ 4.4 WebView 加固 → 4.5 列表体验（A3）
4. 全程不动 C 级清单所列项；每项独立 PR + 回归测试。

---

*文档版本：v1.4（2026-09-11）。分析基线 `8f76f51`。第二/三阶段展开前须由 Human Owner 立项。*
