# Changelog

> 正式版本历史（用户视角：发生了什么）。详细发布证据、验证记录见 [docs/releases/](docs/releases/)（工程师视角：这次发布是怎么证明的）。

## [0.3.0] - 2026-10-13（tag v0.3.0，`versionCode` 3 → 4）

首个多平台版本：Windows 桌面端 MVP 上线。累计 6 个 commit（v0.2.0 → v0.3.0）。

### 新增

- **Windows 桌面端**：`tafcm.exe` 可独立运行的 Windows x64 桌面应用，基于 WebView2 Runtime（Windows 10 1803+ / Windows 11 默认内置）。详见 [ADR-0034](docs/decisions/ADR/0034-windows-desktop-platform.md)。
- **Windows 构建 CI**：`build-windows` CI job，路径过滤 + 手动触发（`workflow_dispatch`），避免每次 PR 跑全量 Windows 构建。
- **Windows 安装节**：`README.md` 新增 Windows 安装指南。

### 已知问题（Windows）

- **编辑器内公式实时 SVG 渲染降级**：Windows 上公式块显示为 `flutter_math_fork` 渲染结果（可用但非 MathJax SVG 原始质量）。根因：`flutter_inappwebview_windows 0.6.0` 的 CDP `Runtime.consoleAPICalled` 事件不回传 Dart，导致 SVG 结果无法通过 `console.log` 协议回传。修复路径明确（Dart 端轮询 DOM 替代等待 console 消息），已登记为 BUG-004，属 Phase 4.2 功能增强。详见 [验证报告 §4.7](docs/releases/phase4.1-windows-mvp-verification-report.md)。
- **Mermaid 图表显示源码占位**：同上根因，Mermaid 图表在 Windows 编辑器内显示源码文本而非渲染后的图表。
- **导出 PDF/DOCX/TXT 不受影响**：导出管线走离屏 canvas 捕获，不依赖 WebView，Windows 上导出功能完整可用。

### 兼容性

- **Android**：`versionCode` 3 → 4 单调递增，已有 Android 安装可直接覆盖升级，本地文档数据不受影响。
- **Web / iOS**：未受影响，平台代码零变更。
- **Windows**：需安装 [Microsoft Edge WebView2 Runtime](https://developer.microsoft.com/en-us/microsoft-edge/webview2/)（Windows 10 1803+ / Windows 11 默认已内置）。

## [0.2.0] - 2026-10-12（tag v0.2.0，`versionCode` 2 → 3）

首个 pre-1.0 里程碑：写作与导出能力增强。累计 135 个 commit（v0.1.1 → v0.2.0）。

### 新增

- **公式语法错误反馈**：公式渲染出错时在编辑器内直接标出错因与位置，插入公式对话框接入 WYSIWYG 实时预览（#374）
- **WYSIWYG 工具栏「块级公式」入口**：无需手敲 `$$`，一键插入独立成行的公式块（#371）
- **解析能力补齐**：Setext 标题（`===` / `---` 下划线式）、四空格缩进代码块、粗斜体 `***x***`、多行 `$$...$$` 块级公式（#376 / #346）
- **文档重命名 + BACK 未保存确认**：改名不再丢数据，误触返回先确认；同名文档加消歧副标题（#368）
- **文件页完整入口**：搜索 / 导入 / 新建入口补齐，首屏搜索按钮真正接回（#370）
- **外部 .md 只读查看**：从外部导入的文档不再"可编辑但退出即丢"，改为只读查看（#369 / #279）
- **Mermaid 主题联动**：图表随 Dark / Sepia 主题切换重新渲染，不再固定浅色（#284）
- **Word 导出真并发**：公式与 Mermaid 同批并发渲染，大文档导出显著提速（#307）
- **导出文件名跟随标题**：导出文件名取首个 H1 标题块，不再一律 `untitled`；用户可控 title 已消毒（#361）

### 修复

**数据安全（防静默丢失）**

- 自动保存生命周期竞态修复：退出编辑页时，在飞的保存回调不再因触碰已释放状态而误报"保存失败"（数据实际已落盘，仅簿记异常，三层防御彻底闭环）（#379）
- Mermaid 渲染器离屏宿主在重渲染后恢复 WebView 就绪状态，消除图表偶发"渲染超时无响应"（#380）
- 文档文件缺失时可自愈 + 列表流容错，杜绝静默数据丢失（#352）
- FrontMatter 未闭合 `---` 按原文处理，杜绝保存吞正文（#345）
- 保存保留段落空行，杜绝相邻段落合并塌缩（#344）
- GBK 文档导入自动兜底解码，不再乱码（#350）

**编辑器输入**

- 标题块末尾按 Enter 新建段落块，不再延续标题类型污染输入（#355）
- 长按选中改为移动判定，慢速横划表格不再被选中打断（#356）
- 横屏下正文内容块不可见已修复（#348）
- 底栏显示真实保存状态；文档加载后自动聚焦首块（#372）
- 术语统一为「文件 / 大纲」，清除菜单工程术语（#375）

**导出与渲染**

- Word 公式 displayMode 取自 AST，PNG 缓存 key 补 displayMode 维度，行内 / 块级公式不再混用（#360）
- 导出中按 BACK 先确认，退出即协作取消并清理浮层（#353）
- 公式导出空白修复：SVG `defs`/`use` 内联 + 离屏捕获透明 PNG（#277 / #278）
- MathJax 字形静默丢弃已修复，导出公式可见性有守门测试（#296）
- 导出超时防护 + 序列化只做一次（#298）
- Mermaid 主题名裸插值致 JS SyntaxError、图表全量失败已修复（#347）

**性能**

- 按键局部化刷新，消除每次按键整树重建（#300）
- 块查找 List→Map，O(n) → O(1)（#299）
- wordCount 增量维护，消除按键 O(n²) 全文档序列化（#280）

**架构与卫生**

- 抽取共享公式收集 dispatcher，消除 word / pdf 三处重复（#377）
- 消除 3 个 Provider 重复定义，删除 2 个死文件（#282）
- 启动流程统一进 `runZonedGuarded`，消除冷启动 Zone mismatch 警告（#365）
- 解析器与存储层代码卫生批量修复 8 项（#366）
- 关于页版本号改为真实版本，文案中文化（#373）

### 安装

- **app-release.apk**：普通用户安装（Android 8.0+，release 构建，已优化）
- **app-debug.apk**：开发者安装（含调试日志，体积较大）

> 两个包均为 debug key 签名（项目未配置生产签名配置），仅适用于本地 / 自签分发，不适用于 Google Play 上架。

### 兼容性

`versionCode` 2 → 3 单调递增，已有安装可直接覆盖升级，本地文档数据不受影响。

### 已知问题

发布验收（本地模拟器全量 E2E）期间发现一批**预存在**的模拟器 E2E 用例失败，与本次修复无关（已在修复前的 commit 上复现同一失败以确认）：

- Undo/Redo 工具栏按钮状态、Block 手柄拖拽、自动续列表等约 18 个模拟器 E2E 断言。这些领域在单元 / Widget 测试层有完整覆盖且全部通过；失败集中在模拟器手势与 UI 状态同步断言层面。
- 根因：CI 工作流的 `Android Device Integration (emulator)` 步骤被路径过滤跳过（`paths-ignore: flutter_app/integration_test/**`），上述用例此前从未在 CI 或本地模拟器上全量运行过，本次发布验收是首次暴露。
- 影响：已确认无用户数据损失、无应用层异常。已登记为独立跟进项，不阻塞本次发布。

## [0.1.1] - 2026-08-31（补丁发布，tag v0.1.1）

- **应用图标替换**：新 favicon 应用到 Android / Web / iOS 全平台（flutter_app/assets/icons/favicon.png 为源文件）

## [0.1.0] - 2026-08-30（首个正式发布，tag v0.1.0）

首个可运行版本，Phase 0-3.11 完成。核心能力：

- **品牌改名** FormulaFix → **Tafcm**（L0+L1 代码层 + L2 叙事 + 工程资产整理）
- **自动代码审查**：claude-review 退役 → Cline（AGNES OpenAI-compatible 网关）+ Copilot review
- **知识体系三层化**：新增 `docs/principles/` + Engineering Handbook 入口

- **块级 WYSIWYG 编辑**：8 种 BlockType + Transaction 模型 + Undo/Redo
- **公式渲染**：LaTeX → SVG 矢量 + PNG 回退（真机验证）
- **Mermaid 图表**：WebView 渲染 → SVG 嵌入导出
- **导出**：Markdown / Word / PDF / 文本（SVG 矢量硬约束）
- **主题**：Light / Dark / Sepia（Design System Token 驱动）
- **便携查看器**：任意来源 .md 即开即看（ACTION_VIEW 注册）
- **可观测 / ADI**：渲染追踪 + Agent Diagnostic Interface

> 版本号沿用 `pubspec.yaml`（0.1.0+1）；正式发布前将接入动态版本读取。

<!--
维护规则：每个正式版本在此追加条目（Keep a Changelog 风格）；
详细证据不在此重复，指向 docs/releases/ 对应报告。
-->
