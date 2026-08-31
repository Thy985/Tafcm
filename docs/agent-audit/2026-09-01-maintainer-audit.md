# Tafcm Daily Maintainer Audit — 2026-09-01

**审查范围**：源码 / 测试 / Issues / PRs / CI / ADR / contracts / 真机证据资产 / 外部生态
**Repo 状态**：`Thy985/Tafcm` @ main `985033dc`（2026-09-01）
**执行**：Maintainer Audit Agent（只读分析为主，Issue 操作经维护者授权）

---

## 1. Repository Health

| 项 | 状态 | 说明 |
|---|---|---|
| CI | ⚠️ 异常 | `main` 最近 4–5 次 merge 的 **Golden (compare)** job 全部失败（run `33403769658`/`33398279483`/`33391709227`，含最新 HEAD `985033dc`）；Analyze / Test / Build / ADI-E2E 均绿。失败步骤：`Run golden tests (compare mode)` |
| Tests | ✅ | `flutter analyze` 0/0；`flutter test --exclude-tags golden/perf` 通过；golden 比对常红（见 F4） |
| Build | ✅ | Web + Android Debug APK 均成功 |
| Architecture | ⚠️ | 公式渲染三路并行（MathJax-SVG / offscreen-PNG / 编辑器 flutter_math_fork），输出互相不一致（见 §5）；ADR-0032 缺失（F5） |
| Known regressions | ⚠️ | Issue #216 导出公式空白（未修复）；#215 已修复待关闭 |

**GitHub 状态**：0 个开放 PR；2 个开放 Issue（#215、#216）；1 个关闭 Issue（#147）。

---

## 2. New Findings

### F1 — SVG→PDF 矢量路径无法渲染真实 MathJax 输出（`<use>` 字形被画成占位符）
- **Category**: Correctness / Runtime · **Severity**: P1 · **Confidence**: HIGH（静态证据闭合）
- **Problem**: `svg_to_pdf.dart` 对 `SvgUse` 节点调用 `_drawUnsupported(...)`，把每个 `<use>` 字形画成 `[unsupported: <use href="#...">]` 文本。`mermaid_renderer.html` 配置 `MathJax = { svg: { fontCache: 'global' } }`（默认），真实 `tex-svg.js` 输出正是 `<defs>` 存字形 + `<use xlink:href>` 引用。解析器 `svg_parser.dart` 直接丢弃 `<defs>` 内容、`<use>` 不解析引用目标 → PDF 公式字形无法矢量呈现。
- **Evidence**: `svg_to_pdf.dart:246`（SvgUse → _drawUnsupported）；`mermaid_renderer.html:8`（fontCache:'global'）；`svg_parser.dart`（defs 丢弃 / use 不解析）；`svg_to_pdf_integration_test.dart` 的“MathJax 风格”用例用的是伪造内联 `<path>` SVG，未覆盖真实 `<use>` 结构。
- **Impact**: PDF 走 SVG 路径时公式必然异常。
- **Recommendation**: **CREATE ISSUE**（归入 #216 根因）→ 解析期实现 `<use href="#id">` → 内联 `<defs>` 对应 `<path>` 的引用解析。

### F2 — FormulaRenderHost 离屏捕获被 `Opacity(opacity: 0.0)` 包裹，疑似产出全透明 PNG
- **Category**: Correctness / Runtime · **Severity**: P1 · **Confidence**: MEDIUM（强静态证据，需真机 PoC 定案）
- **Problem**: `formula_pdf_renderer.dart:214` 的 `_OffscreenCapture.build` 把待捕获的 `RepaintBoundary` 子树包在 `Opacity(opacity: 0.0)` 里。`RepaintBoundary.toImage()` 合成 layer 树时应用 alpha=0 → PNG 全透明 → Word（恒走此 PNG 路径）与 PDF（SVG 缺失时 fallback）嵌入透明图 → 公式空白。这是唯一能解释“Word 空白且非文本化”的机制。
- **Evidence**: `formula_pdf_renderer.dart:209-242`；`word_exporter.dart` `preRenderAll` 100% 走此路径；BUG-WORD-001 修复（widthEmu>0 才嵌图）不拦截透明 PNG（尺寸合法）；历史真机验证只断言“不崩溃/字节非空/fallback 文本存在”（`docs/releases/phase3.5-realdevice-issues.md` E2E-P0-8），从未验证 PNG 像素可见性。
- **Impact**: Word 公式必现空白；PDF 在 WebView/SVG 失败时也空白。
- **Recommendation**: **INVESTIGATE**（#216 首要排查项）→ 真机 PoC 检查导出 PNG alpha 通道；修复方向：捕获体改为不透明但不可见的容器。

### F3 — 没有任何测试验证“导出的公式是可见的”
- **Category**: Test Gap · **Severity**: P1 · **Confidence**: HIGH
- **Problem**: 导出公式相关验证只断言“不崩溃 / 字节非空 / `%PDF` 头 / fallback 文本存在 / rels 与 media 数量一致”。`word_export_semantic_fidelity_test.dart:107-108` 明确注释测试环境无渲染器 → widthEmu=0 → 走 fallback，即只测了 fallback 分支。无用例检查渲染公式 PNG 非透明 / PDF 有真实字形 / 真实 `<use>` SVG 可渲染。
- **Evidence**: 全测试目录无 alpha/pixel 断言；`docs/releases/phase3.5-realdevice-issues.md:371` 官方承认公式质量留人工验收；F1/F2 正是该缺口直接后果。
- **Impact**: 导出公式核心卖点回归只能靠人工，已被真实用户（#216）踩中。
- **Recommendation**: **CREATE ISSUE** → 补两层测试：① PNG alpha 非全透明；② 真实 MathJax `<use>` SVG 渲染断言。

### F4 — main 的 Golden (compare) CI 持续红，且 112 个失败产物被强行入库
- **Category**: CI / Regression Risk · **Severity**: P1 · **Confidence**: HIGH
- **Problem**: Golden job 是项目自己的视觉回归保护（ci.yml 注释：任何像素 diff 即失败），但最近 4–5 次 main/PR merge 全部失败，docs-only PR（#218/#219）仍带红 baseline 合入。`flutter_app/test/golden/failures/` 虽在 `.gitignore` 中，却有 112 个 git-tracked PNG。
- **Evidence**: Actions runs API `33403769658`/`33398279483`/`33391709227` Golden job failure；`git ls-files flutter_app/test/golden/failures/` = 112；`.gitignore:53` 声明该目录应忽略。
- **Impact**: 视觉回归信号被静默容忍；仓库混入生成产物。
- **Recommendation**: **CREATE ISSUE** → 判定基线过期 vs 真实回归（`update_goldens` 重建基线对照）；`git rm --cached` 清掉 112 个入库 PNG。

### F5 — 被引用的 ADR-0032 不存在
- **Category**: Docs / Architecture Drift · **Severity**: P3 · **Confidence**: HIGH
- **Problem**: #216 正文引用 `docs/decisions/ADR/0032-export-assembly-finite-guarantee.md`，PR #213/#214 提交信息均称“P0-D（ADR-0032）”，但仓库中无该文件（`docs/decisions/ADR/` 最新为 0031，全仓 grep “0032” 无命中）。
- **Impact**: P0-D 公式密度降级（用户可见的导出质量取舍）无决策留档。
- **Recommendation**: **IGNORE（记录）** → 补写 ADR-0032，顺带修正 ADR 编号（0025 出现两次、缺 0026/0027）。

### F6 — ADR-0022 退役链接指向错误
- **Category**: Docs · **Severity**: P3 · **Confidence**: HIGH
- **Problem**: `docs/decisions/ADR/0022-renderer-failure-policy.md`“退役原因”链接到 `../ADR/0031-rebrand-tafcm.md`（品牌改名 ADR），但内容说的是 P0-1 WYSIWYG 修复轮（PR #176）——链接目标与语义不符（PR #189 死链修复轮漏掉此处）。
- **Recommendation**: **IGNORE** → 顺手改正链接目标。

---

## 3. Existing Issue Investigation

### Issue #216 — 导出的公式渲染不正常（空白/缺失）
- **Current status**: OPEN，用户已确认“任何公式”在 PDF 和 Word 均空白（非 `[$...$]` 文本、非乱码）→ 排除 P0-D 密度降级。
- **Likely root cause**: 两个独立缺陷叠加，均以“空白”呈现：
  1. **F2（主嫌疑）**: Word 恒走 `FormulaRenderHost` → `Opacity(0)` 捕获 → 透明 PNG；PDF 在 WebView 预渲染失败时回落到同一 PNG 路径 → 双双空白。
  2. **F1（次嫌疑，PDF 独立）**: 即便 WebView 正常，SVG 路径的 `<use>` 字形也会被画成占位符/裁剪不可见。
- **Evidence**: 见 F1/F2 代码路径；phase3.5 报告（E2E-P0-8 只验“不崩溃”）。
- **Related code**: `formula_pdf_renderer.dart:209-242`、`svg_to_pdf.dart:246`、`svg_parser.dart`、`pdf_exporter.dart:139-175`、`word_exporter.dart:122`
- **Related ADR**: ADR-0032（缺失）；BUG-WORD-001 修复记录（`docs/archive/audits/WORD-EXPORT-PRODUCT-RELIABILITY-AUDIT.md`）
- **Recommendation**: ① 真机 PoC 验证 F2（检查导出 PNG alpha）；② 复现最简文档导出，logcat 采集 `SvgPlan`/`PNG fallback`/`FormulaQuality` 确认 PDF 走的路径；③ 修复后为 F1/F2 各补一条回归测试。

### Issue #215 — 导出完成 SnackBar 残留
- **Current status**: OPEN，但修复已合入：PR #214 已 merge（`92e6949`），代码验证通过——`editor_export_actions.dart:117` 已改 `unawaited(Share.shareXFiles(...))`，`export_progress_overlay.dart:55-76` 已有 dispose 时 postFrame 清全局 SnackBar + 强制 reset。
- **Recommendation**: 确认新包真机复测后关闭（2026-09-01 已在 issue 添加验证评论）。

---

## 4. Ecosystem Watch

### E1 — 公式渲染三路栈（MathJax-SVG / offscreen-PNG / flutter_math_fork 编辑器）
- **What changed**: `flutter_math_fork` 最新 0.7.4（约 15 个月前发布，simpleclub 维护）；它是无人维护的 `flutter_math` 的 fork，仍是 Flutter 生态 LaTeX 渲染事实标准。
- **Why it matters**: 同一公式三处渲染、三种输出，视觉天然不一致，且 #216 暴露两端导出均异常。
- **Current approach**: 三路并行，WebView+MathJax 是唯一矢量源。
- **Alternative**: 用 flutter_math_fork（已内置）统一渲染，去掉对离屏 WebView 依赖；但它不原生输出 SVG，需自研 `ui.Picture`→PDF 桥接。
- **Migration cost**: 中–高 · **Recommendation**: **INVESTIGATE**（小型 PoC），暂不迁移——先修复 F1/F2。

### E2 — 自研 SVG→PDF 渲染器（svg_parser + svg_to_pdf，~760 行）
- **What changed**: 生态替代 `pw.SvgImage`（pdf 包）仍已知在 utf8 边界抛错；无成熟 drop-in 替代同时满足“矢量 + CJK + utf8 边缘字符”。
- **Current approach**: 自研 AST + 直通 `canvas.drawShape`。
- **Alternative**: 解析期展开 `<use>` 引用（修复方向，非迁移）。
- **Migration cost**: 低（修复）vs 高（迁移） · **Recommendation**: **KEEP**（补 `<use>` 解析即可，自研方案在 utf8/矢量约束下仍有价值）。

### E3 — flutter_inappwebview（WebView 公式渲染底座）
- **What changed**: 稳定版 6.1.5 发布于约 19 个月前；6.2 仍为 beta。Tafcm 钉在 6.0.0 + `platform_interface 1.3.0+1` override。
- **Why it matters**: 整个 PR-1/PR-2/PR-D/专项2 系列都在与“真机离屏 WebView 页面加载不稳定”搏斗；插件稳定版已约 1.5 年未动，Android 新机型兼容风险在积累。
- **Current approach**: 离屏 WebView + MathJax 做矢量源。
- **Alternative**: 无成熟同功能替代；只能接受不稳定性并做好降级链。
- **Migration cost**: 高 · **Recommendation**: **KEEP**（注意升级到 6.1.x + 平台包同步；长期降低 WebView 在导出主链路的权重）。

### E4 — Word 公式以 PNG 图片嵌入（无 OMML）
- **What changed**: 无外部变化；Word 迁移 spike（2026-08-18）已判定 `docx_creator`/`docs_gee` 因依赖冲突无法集成。
- **Current approach**: 自研 OOXML builder，公式 = PNG 图片（不可编辑）。
- **Alternative**: 原生 OMML（Office Math）才是 Word 公式正解（可编辑、无图可破），工程量不小。
- **Migration cost**: 高 · **Recommendation**: **KEEP**（PNG 嵌入是当前合理折中；OMML 列入 backlog）。

---

## 5. Architecture / Technical Debt

1. **公式渲染三路并行（最高优先技术债）**：同一 LaTeX 在编辑器（flutter_math_fork）、PDF（MathJax SVG）、Word（offscreen flutter_math_fork PNG）三处渲染，输出不一致且维护面×3。F1/F2 都源于此。
2. **ADR-0032 缺失**（F5）：导出质量降级决策未留档。
3. **golden failures/ 混入版本库**（F4）：生成产物突破 gitignore 语义。

---

## 6. Test / Regression Gaps

按价值排序：
1. **导出公式“可见性”断言**：PNG alpha 非全透明 + 真实 MathJax `<use>` SVG 渲染断言（防 F1/F2 回归，也防 #216 复发）。最值得补。
2. **真实 MathJax 输出 fixture**：用 `tex-svg.js` 实际产出的 SVG（`<defs>`+`<use>`）替换当前伪造内联 path 的用例。
3. **CI golden 基线校准**：判定 stale baseline vs 真实回归，并恢复 failures/ 忽略语义。

---

## 7. Recommended Actions（最多 3 项）

1. **Investigue #216 根因并修复公式导出空白** —— 真机 PoC 验证 F2（`Opacity(0)` 透明 PNG）为第一排查项，同时修复 F1（SVG `<use>` 引用解析）；修复后补“公式可见性”回归测试。这是用户直接踩中的 P1。
2. **恢复 main CI 绿色** —— 处理 Golden (compare) 持续失败（重建基线 or 修回归），并清理 112 个被强制入库的 golden failure PNG。
3. **补录 ADR-0032**（P0-D 导出组装有限性决策）+ 关闭 #215（修复已合入 #214）+ 修正 ADR-0022 链接。

---

*每日结论：存在真实值得关注的问题。核心是 #216 导出公式空白（两个独立缺陷：SVG `<use>` 不可渲染 + 疑似透明 PNG），以及 main CI golden 持续红。*