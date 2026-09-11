# 测试体系升级规划 — 基于外部参考项目调研

> **触发**：基于 [EXTERNAL-PROJECTS-EMPOWERMENT-PLAN.md](../product/EXTERNAL-PROJECTS-EMPOWERMENT-PLAN.md) §8-11 的调查结论，Human Owner 要求调研 4 个参考项目（Markor / Markwon / Jota / SoloMD）的测试体系，升级本项目测试体系。
> **分析基线**：`feat/firebase-appbar-e2e` @ `8f76f51`（2026-09-11）
> **性质**：规划文档（Analysis + Plan，零代码改动）。执行须按 AGENTS.md 走 PR 流程。

---

## 0. 核心判断（评审定调）：不是数量问题，是测试维度问题

> 192 个测试文件在四个参照项目里已属高量级。真正的问题不是"测得少"，而是：
>
> **"我们测了很多" ≠ "我们测到了最危险的地方"。**
>
> 测试的结构尚未完整覆盖一个 Markdown Document Runtime 的真实风险面——尤其是**数据生命周期**维度。

### 0.1 数据生命周期测试矩阵（评审核心增量）

以"导出时代码消失"类 bug 为例：它完全可能出现于单测/集成测试全绿、唯独生命周期末端断裂的场景：

```
Parser ✅ → AST ✅ → Editor ✅ → Renderer ✅
  → Unit ✅ → Integration ✅ → Export ❌   ← 测试矩阵没盖到的末端
```

因此每条升级项（§3）都要回答：**它守的是生命周期的哪一段**。全链分为六段，现有覆盖与新增项映射如下：

| 生命周期段 | 现有覆盖 | 本规划新增 |
|-----------|---------|-----------|
| 输入解码（bytes→text） | file_service_decode_test（合成样本） | U6 真实样本 corpus |
| 解析（text→AST） | edge_case/fuzz | U1 spec 套件 |
| 编辑（AST↔AST 事务） | editing 29 文件 + undo fuzz | U4 不变量守门 |
| 渲染（AST→UI） | golden + presentation 46 文件 | U2 IME 矩阵（输入→AST 段） |
| **序列化回写（AST→text）** | serializer 11 例 | U4（I1/I2 断言） |
| **导出（AST→外部格式）** | export 集成若干 | U4（I5 断言）+ 一键验证出口 |

### 0.2 测试层次经济学（Markor 的真实启示）

Markor 成熟但只有单测——启示**不是"测试少也行"**，而是：

- **越靠近 UI，测试越贵；越靠近纯逻辑，测试越便宜**。不要用昂贵测试替代廉价测试；
- 不要因已做 E2E 就产生"什么都该 E2E"倾向：parser 边界情况用 `input→expected AST` 即可，不必启动 App 走 UI；
- 层次金字塔保持：Unit（大量细粒度）→ Integration（业务边界）→ E2E（**少而关键**）。

### 0.3 外部指标 vs 内部指标（Markwon 的真实价值）

"Parser 测试有 87 个"是**内部指标**；"CommonMark 兼容率 90.8%，其中 List 81%、Emphasis 89%"是**外部质量指标**。规格驱动把测试从"开发者想到了多少"变成"规范规定了什么"（specification-based testing）——§3.1 U1 按此重述价值。

### 0.4 成熟能力由成熟依赖提供（Jota 的真实价值）

"无可借鉴测试体系"判断过于悲观。Jota 的编码能力实为 UniversalChardet（成熟库自带测试）——**能力外包给成熟依赖，测试建立真实文件 corpus 验证完整生命周期**：`fixture → detect → decode → parse → serialize → 语义不丢失`，而非断言 `decode() 返回某字符串`（§3.6 U6 按此升级）。

### 0.5 真实环境盲区（SoloMD 的真实价值）

262 个单测+集成仍漏掉真实使用 bug——证明 unit/integration 存在天然盲区：**Real Environment**（IME、真实键盘、真实路径、真实权限）。两个推论：① IME 从"开发注意事项"升级为测试矩阵（§3.2）；② 文件路径安全从 UI 层问题升级为 **Agent Tool Boundary** 问题——未来 Agent 可调用 export/write/save/open，路径穿越测试就是 Agent 权限边界的第一道闸（§3.3）。

### 0.6 Verification 必须机器可消费（一键验证入口）

Markor `make test` 把测试/报告/产物统一为一个工程入口。对 Agent-native 定位的 Tafcm，这不是锦上添花：

> Agent 与 Human 都应只问"Tafcm 当前是否健康？"，而不是记住"先跑这个命令、再看那个目录、再查那个 JSON"。

Verification 必须成为**机器可消费的接口**——新增 U0（§3.0）。

---

## 1. 四个参考项目的测试体系调研

### 1.1 Markor（Android 应用，Java，Apache 2.0）

| 维度 | 实况 |
|------|------|
| 测试形态 | **仅单元测试**。作者 gsantner 亲述（2025-05，issue #2584）："currently there is only unit testing. No automated UI testing/end-to-end testing"，且明确不希望 UI 测试覆盖太广（贡献者不愿维护） |
| 测试驱动 | Makefile 一条龙：`make test` = `testFlavorDefaultDebugUnitTest` + 结果 XML 归档到 `dist/`；`make lint`、`make deptree` 同构 |
| 报告 | build.gradle 全局配置 JUnit XML + HTML 双报告、逐用例 stdout |
| 回归实践 | 社区贡献者主动为历史 bug 补 UiAutomator 回归测试（issue #2584 文件扩展名重复 bug），**但这类测试不进 CI**，仅作 issue 附件 |
| parser 测试 | 不自测 parser——直接用 flexmark-java 库（库自身带 CommonMark spec 套件） |

**可借鉴**：Makefile 式"一条命令全验证"的工程化封装；JUnit XML 归档；"UI 测试宁缺毋滥"的维护性权衡。

**不可借鉴**：测试广度本身（我们 192 个测试文件已远超它）。

### 1.2 Markwon（Android 渲染库，Apache 2.0）

| 维度 | 实况 |
|------|------|
| 测试形态 | **spec 一致性套件为核**：依托 commonmark-java 的 `commonmark-test-util`，把 `spec.txt`（CommonMark 0.31.2，**500+ 内嵌一致性用例**）作为参数化测试数据源 |
| 用例格式 | spec.txt 内嵌 `markdown ↔ html` 侧栏对照，可用 `spec_tests.py` 跑任意实现，也可导出 JSON：`{"markdown": "...", "html": "...", "section": "Setext headings", "number": 65}` |
| 扩展测试 | GFM 扩展（table/strikethrough/tasklist）有独立 extension 测试；渲染层 Span 断言有专门 TL;TR 风格用例 |
| 许可 | spec.txt 是 **CC-BY-SA 4.0**——可直接用作我们的测试数据（注明出处） |

**可借鉴（本次调研最大收获）**：**"规格即测试数据"范式**——不手写用例，直接吃标准 spec 文件做参数化。我们 parser 缺口（§9 的 60-70% 覆盖）正需要这种度量方式。

### 1.3 Jota Text Editor（Android 应用，Apache 2.0）

| 维度 | 实况 |
|------|------|
| 测试形态 | **无可观测测试体系**：仓库 2019 年后停更，无 test 目录约定、无 CI 配置可考 |
| 可提取的资产 | 其编码探测依赖 **UniversalChardet**（Mozilla 库，自带测试）——这是它"多编码"能力的真正来源，不是它自己测出来的 |

**结论**：无测试体系可借鉴。但其"编码能力 = 成熟探测库 + 库的测试"提示我们：4.2 编码显式化的测试应基于**真实编码样本文件集**（GBK/Big5/UTF-8 BOM/无 BOM 混合），而非仅单测断言。

### 1.4 SoloMD（Tauri+Vue 桌面/移动应用，MIT）

| 维度 | 实况 |
|------|------|
| 测试形态 | **262 个单元 + 集成测试**（作者在 release notes 中明说"262 unit + integration tests didn't catch"） |
| 发布质量门 | **dogfooding 发布实践**：v4.0 发布说明专设 "What dogfooding caught (so you don't)" 章节——真机+真实 vault+真实 BYOK 才暴露的三类单测漏掉的 bug |
| 关键测试主题 | ① **IME 组合键守卫**（`e.isComposing` 防 Enter 误触发，覆盖 7 个输入面：拼音/假名/Hangul）② **路径穿越安全测试**（`../` 逃逸 workspace 的真实 exploit 用例）③ **数据完整性不变量**（AutoGit 分支沙箱 + write-cap + dirty 拒启——"五个不变量守同一道线"） |

**可借鉴（次大收获）**：
1. **IME composition 测试矩阵**——我们 §10 A1 的回车行为不一致、AGENTS.md §11.3 的 IME 踩坑史，正缺这种跨输入法矩阵测试；
2. **安全边界测试**（路径穿越/写权限）——我们对 file_repository / 导出路径尚无此类用例；
3. **数据完整性不变量断言**——与我们 invariant_checker（ADI）理念相同，SoloMD 验证了这条路值得加厚；
4. dogfooding 门禁 = 我们的 E2E 真机轮（integration_test），已有但可把"发布前必跑"制度化。

### 1.5 调研汇总

| 项目 | 测试形态 | 核心启发 | 广度对比（我们 192 文件） |
|------|---------|---------|------------------------|
| Markor | 仅单测，Makefile 驱动 | 一条命令全验证；UI 测试克制 | 我们远超 |
| Markwon | spec.txt 500+ 一致性参数化 | **规格即测试数据**；兼容率可度量 | 我们缺 |
| Jota | 无 | 编码测试要吃真实样本集 | 无可比 |
| SoloMD | 262 单测+集成 + dogfooding | **IME 矩阵 / 安全边界 / 数据不变量** | 我们量级相当，主题有缺 |
| **vgpu**（vercel-labs，WebGPU 库，2026-09-11 补充调研） | **三运行时验证**（Browser / Dawn headless Node / deterministic mock）+ **pixel readback 数值断言** + `vgpu doctor` JSON 健康检查 | **确定性渲染验证范式**：内部状态→可断言证据 | 范式互补（见 §4） |

---

## 4. vgpu 范式迁移分析（2026-09-11 补充）

> **触发**：Human Owner 提出 [vercel-labs/vgpu](https://github.com/vercel-labs/vgpu) 并给出"确定性渲染验证思想迁移"的完整分析。
> **结论先行**：vgpu 作为依赖**不集成**（WebGPU/TS 图形库与 Flutter 无关）；其"确定性执行 / 机器可读证据 / 数值断言先于视觉判断"的**测试方法论值得吸收**。但需先纠正一个前提偏差（§4.1），再吸收（§4.3）。

### 4.1 前提校正："Golden 承担过重"在本项目不成立

Human Owner 的分析框架（语义 > 结构 > 视觉、Visual Testing Ladder、证据下钻）方向正确，但有一个关键事实需要修正：

- **我们的 golden 从未承担"Document Correctness"职责**。实测：14 个 golden 文件（占 192 个测试文件的 **7%**）全部是纯视觉断言（`matchesGoldenFile`，无 expect/finds 语义断言），且被 CI `--exclude-tags golden` 拆到独立 job——它已经是"最后一层视觉回归"，不是"核心验证手段"。
- **语义/结构层测试已大量存在且是主力**：round-trip fuzz（2001 轮）、edge_case 23 例、undo_redo_fuzz、ADI invariant_checker、TC-ARCH 守门——§2.3 强项清单。
- 因此本次升级**不是"降维 Golden"**（它已在正确的位置），而是 Human Owner 分析中真正有价值的部分：**给确定性管线补"中间层快照"与"证据下钻"**。用户举例的 CodeBlock 导出丢失 bug，正确的防御位置是 U4 不变量守门（export→reparse→AST 恒等断言），这正好印证 §3.4 的设计。

### 4.2 vgpu 值得吸收的六个实践（已核实 getting-started 文档）

| # | vgpu 实践 | 翻译到 Tafcm |
|---|----------|-------------|
| V1 | `npx vgpu doctor`：JSON verdict（healthy/unhealthy，每个问题附精确修复处方） | 强化 `ffx adi doctor`：当前已有的自检扩展为"环境+基线+不变量"三段 JSON verdict，产出机器可消费 |
| V2 | **pixel readback**：不判断"PNG 是否生成"，直接 `target.read()` 断言 RGBA 字节 | golden 断言从"文件存在/整体 diff"升级为关键区域像素采样断言（如：公式渲染区非空白、主题切换后背景色值命中 token） |
| V3 | **internal values → pixels → diff CPU reference**（shader 调试案例：肉眼两轮无果，编码内部值到像素一次定位） | 渲染链各层（AST → Layout → Render Model → Widget）提供 **debug snapshot 导出**（nodeType/language/contentHash JSON），失败时逐层 diff 定位断点层——即"证据下钻" |
| V4 | **deterministic mock runtime** 专为 tests/CI 服务 | 渲染管线确定性化：Mermaid/公式 WebView 渲染在测试中注入 deterministic fake（固定尺寸 SVG），使 CI 不依赖字体/GPU/设备差异 |
| V5 | 同一套 API 跨运行时（Browser/Node/mock） | 语义测试族（U1/U4）必须纯 Dart 可跑（无真机依赖）——已满足，制度化 |
| V6 | "Every visual claim backed by pixels you actually read" | golden 基线更新必须附 diff 证据（现有 golden-diffs artifact 已达成，保持） |

### 4.3 新增升级项（并入 §3 排期）

| 项 | 内容 | 优先级 | 工作量 | 对应 §3 缺口 |
|----|------|--------|--------|-------------|
| **U8** **Layered Debug Snapshot** | `Markdown → AST → Layout → RenderModel → Widget` 每层可导出 JSON snapshot（含 contentHash），配套 `test/evidence/` 逐层对拍测试；新增缺陷报告时按层标注（AST ✅ / Render ❌ / Export ❌） | P1 | 3-4 人日 | 新增（补 V3 证据下钻；ADI render_tracer 已有采集面可复用） |
| **U9** **Export Semantic Snapshot** | export→reparse→AST' 恒等断言（`∀ supported node n: semantic(n) == semantic(roundTrip(n))`），覆盖 Human Owner 举例的 code block 导出丢失类 bug | P0 | 2 人日 | 并入 U4（不变量守门的第一个落地场景） |
| **U10** **Pixel Region Sampling** | golden 测试增加关键区域像素值断言（V2），先从公式块"非空白"与主题背景 token 值两处试点 | P2 | 1-2 人日 | 增强 golden 层（不改其定位） |

**Visual Testing Ladder 采纳说明**：Human Owner 提出的 L0 存在/L1 结构/L2 数值/L3 视觉四层——我们现有体系**天然已分层**（smoke_test=L0、TC-ARCH/存在性断言=L1、fuzz/edge_case/invariant=L2、golden=L3），无需新建框架；U8/U9 是把 L2 在**导出与渲染中间层**补厚。Golden 定位表述采纳为："证明同一个正确 Document 的视觉输出无非预期变化"（§2.2 门禁链现状与此一致，仅补充 U10 试点）。

### 4.4 调研汇总表更新（六参照版）

```
Markwon  → Specification Testing     （U1）
SoloMD   → Invariant / Real-world    （U2/U3/U4/U7）
Jota     → Real Corpus / Boundary    （U6）
Markor   → Verification Workflow     （U5/CI 工程化）
vgpu     → Deterministic Rendering / Numeric Evidence（U8/U9/U10）
```

---

## 2. 我们现有测试体系盘点（2026-09-11 实测）

### 2.1 规模与分布（192 个 *_test.dart）

| 目录 | 数量 | 覆盖 |
|------|------|------|
| presentation/ | 46 | widget/交互 |
| observability/ | 32 | ADI/追踪/不变量 |
| editing/ | 29 | 事务/undo/serializer（含 `undo_redo_fuzz_test`） |
| architecture/ | 22 | 守门（TC-ARCH-*、file_access、file_size、provider_uniqueness） |
| golden/ | 14 | 视觉基线（Linux CI 生成 + 比对，diff artifact） |
| integration/ | 9 | 渲染数据流/导出链 |
| parser/ | 6 | edge_case 23 例 + roundtrip_fuzz + serializer + mermaid/table audit + A/B spike |
| performance/ | 3 | block/list/parser perf |
| 其余 | 31 | storage/error/export/widgets/顶层 |

另有 `integration_test/`（Android 真机/模拟器 E2E，单文件 ~50s、全轮 ~18min）与 ffx-cli 侧 170+ pytest。

### 2.2 门禁链（ci.yml）

1. `flutter analyze --no-fatal-infos --fatal-warnings`
2. `flutter test --exclude-tags golden --exclude-tags perf`（golden/perf 拆独立 job）
3. golden job：Linux 基线比对，失败上传 `golden-diffs` artifact；`update_goldens` 手动触发基线再生
4. （E2E 真机轮在独立流水/本地，未在 ci.yml 主链）

### 2.3 相对四个参考项目的强项（保持，不动）

- **round-trip fuzz**（2001 轮锁 BUG-1~6）——Markor/SoloMD 均无此深度
- **架构守门测试**（TC-ARCH 系列）——四项目均无
- **可观测即测试**（ADI fault injection / invariant_checker）——超出全部参照
- golden 基线 CI 化 + diff artifact——Markor 无任何视觉测试

### 2.4 缺口（对照调研结论）

| # | 缺口 | 证据 | 对标 |
|---|------|------|------|
| G1 | **无 CommonMark spec 一致性套件**：parser 兼容率无度量，§9 的"60-70%"只是估计值 | test/parser 无 spec 数据源 | Markwon（最大缺口） |
| G2 | **无 IME 组合测试矩阵**：composing 只在单点测（`cap_ime_composing_test`），无跨输入法场景矩阵（拼音/假名/Hangul × 回车/退格/工具栏） | presentation 仅 1 个 ime 相关文件 | SoloMD 7 输入面矩阵 |
| G3 | **无安全边界测试**：`file_repository` / `external_file_service` / 导出临时文件路径无路径穿越、无越权写用例 | grep 无 traversal/escape 类测试 | SoloMD 路径穿越 exploit 用例 |
| G4 | **数据完整性不变量未成体系**：invariant_checker 存在但仅在 ADI 诊断路径，未作为常规测试断言运行 | observability/ 有实现、test/ 无常态守门 | SoloMD "五个不变量守一道线" |
| G5 | **性能测试无门禁阈值**：3 个 perf 文件存在但 CI `--exclude-tags perf` 后无后续 job 接管，无回归阈值报警 | ci.yml golden job 同款模式缺失 perf 版 | Jota"百万字符不卡"目标（issue #245 正需此防线） |
| G6 | **E2E 未制度化进主门禁**：integration_test 不在 ci.yml，发布前 dogfooding 靠人工记忆 | §13 已知超时风险 | SoloMD dogfooding 门 |
| G7 | **编码测试无真实样本集**：`file_service_decode_test` 用合成字符串，无 GBK/Big5/BOM 真实二进制 fixture | test/ 无编码样本资产 | Jota→UniversalChardet 启示 |

---

## 3. 测试体系升级规划（按优先级）

> 原则：**不推倒现有体系**（强项保持），按缺口补测试族 + 两项工程化。每项独立 PR，遵守 §5.3 检查清单。
> **Tafcm Test Corpus 总纲**：标准负责基础语义，Tafcm 自己负责扩展语义（CommonMark ≠ Tafcm 完整测试）。

### 3.0 U0（P0）：统一验证入口 `tafcm verify` + 三层测试语料 【学 Markor make + Agent-native 定位】

**U0a：一键验证入口。** 把现有分散的验证面（analyze / unit / golden / perf / integration / contracts / evidence 归档）收敛为一个工程入口 `tool/verify`（或 `./scripts/verify`），分层可组合：

```
tafcm verify [--level unit|integration|e2e|all] [--json]
  ├─ static:      flutter analyze --no-fatal-infos --fatal-warnings
  ├─ unit:        flutter test --exclude-tags golden,perf
  ├─ golden:      flutter test --tags golden（Linux 基线）
  ├─ perf:        flutter test --tags perf（阈值门禁，见 U5）
  ├─ integration: 渲染数据流/导出链子集
  ├─ e2e:         integration_test（发布门，见 U7）
  └─ evidence:    结果落 .ffx/ 或 docs/evidence/（复用 ffx-cli 既有管线）
```

设计约束：
- `--json` 输出机器可消费结果（对齐 ffx-cli `_effective_json` 惯例）——**Verification 即 Agent 接口**：Agent 判定"Tafcm 是否健康"只依赖这一个命令，不再记忆多条命令 + 目录 + JSON 的组合；
- 产物归档规则与 Markor `dist/` 对齐：每次运行落 XML/JSON + 失败 artifact（golden-diffs 已有，推广到 perf/integration）；
- 不替代 CI：CI 逐 job 调用 verify 的对应 level，本地与 CI 永远同一条命令（消除 AGENTS.md §11 "本地裸 analyze 漏检"类漂移）。

**U0b：Tafcm Test Corpus（三层语料）。** U1/U4/U6 的测试数据不再各自为政，统一进一个语料仓库 `test/corpus/`：

| 层 | 内容 | 来源 | 消费者 |
|----|------|------|--------|
| L1 标准 | CommonMark spec.txt 用例集（markdown↔AST 对照） | commonmark-spec（CC-BY-SA 4.0） | U1 一致性套件 |
| L2 扩展 | **Tafcm Extensions**：Math（显式/隐式 LaTeX）/ Mermaid / GFM 表格 / 任务列表 / front-matter / WikiLink（未来）——标准之外的扩展语义用例 | 自建（从 §9 缺口 + fuzz 历史 BUG-1~6 提炼） | U1 扩展层、round-trip fuzz |
| L3 产品 | **Product Semantics**：真实样本文件（多编码 fixture、大文件、畸形 YAML、外部 URI 场景）——验证完整生命周期语义不丢失 | 自建 + U6 样本集 | U4 不变量、U6 编码链、集成测试 |

三层的判定规则：
- L1 用例失败 = **兼容性缺口**（记入 spec 通过率表，逐版收敛）；
- L2 用例失败 = **回归 bug**（必须修代码，禁止 skip）；
- L3 用例失败 = **产品语义回归**（数据丢失类直接红，不允许降级）。

> 边界重申（评审）：Markwon 可以大量依赖 CommonMark 是因为它只做 parse/render；Tafcm 是 Document Runtime（WYSIWYG/Math/Mermaid/State/History/Export/Agent），因此 L1 只能占语料一部分，L2/L3 才是与产品风险面对齐的主体。

### 3.1 U1（P0）：CommonMark spec 一致性套件 【学 Markwon】

- **做法**：把 commonmark-spec 的 `spec.txt`（CC-BY-SA 4.0，注明出处）解析为 JSON 用例集（markdown↔html 对照），写入 `test/parser/spec/`；
- **落地形态**：我们 parser 输出 AST 而非 HTML，不能直接比 html——改为**两层**：
  1. **解析层对拍**：用 §11.1 A1 的 commonmark-java（Apache 2.0）跑同一 markdown 生成 AST，与我们 `MarkdownParser.parse` 的 AST 做结构归一化对比（新增 `spike/spec_conformance_test.dart`，复用 A/B 框架）；
  2. **度量报告**：按 spec section 输出通过率表（30 个 section × 通过/失败计数），落 `docs/engineering/` 作为基线——§9 的"60-70%"变成精确数字，且每补一个语法缺口可量化验收；
- **验收**：spec 套件进 CI（允许先 `skip` 失败用例并在表登记，目标是逐版收敛 skip 数，禁止新增 skip）。

### 3.2 U2（P0）：IME/键盘/文档上下文三维输入矩阵 【学 SoloMD】

- **定位升级**：不是"补一个 IME 测试文件"，而是把 IME 从"开发注意事项"（AGENTS.md §11.3 踩坑史）升级为**测试矩阵**——"输入法 ✅ / Editor ✅ / 普通键盘 ✅ / IME+Enter ❌"这类组合 bug，单点测试永远测不到。
- **三维矩阵**：

| 维度 | 取值 |
|------|------|
| 输入法/键盘 | English 直输 / 中文拼音 IME / 日文假名 IME / 韩文 Hangul IME |
| 键盘动作 | Enter / Backspace / 方向键 / 选区拖拽 / 工具栏点击（composition 中触发） |
| 文档上下文 | Paragraph / List / Heading / Code / Math / Table |

- **composing 生命周期断言**（每格矩阵）：composition start → update → **commit** / **cancel** 四态下，上述动作不误触发分块/续行/工具栏动作（对齐 §2.1.1 Hard Rule：`composing == TextRange.empty` 才处理）；
- **落地形态**：`test/presentation/ime_matrix_test.dart`，widget 测试模拟 composing region（`TextEditingValue.composing` 非空 + `TextInput` 原生通道 fake），全部格子参数化（`testWidgets` × 用例表）；真机层抽 3-5 个格子进 U7 E2E 冒烟（拼音 Enter 提交候选是最高风险格）；
- **验收**：矩阵全格绿；§10 A1"两条回车路径不一致"在矩阵中有对应格子并转绿。

### 3.3 U3（P1）：安全边界测试族 【学 SoloMD】

- **定位升级**：路径安全不只是 UI 层问题。Tafcm 是 Agent-native 产品，未来 Agent 可调用 export/write/save/open——**文件路径安全 = Agent Tool Boundary**。本测试族是未来 Agent 工具权限模型的第一道闸。
- **范围**（`test/security/` 新目录，纯 Dart 单测为主）：
  1. `file_repository`：path 参数含 `../`、`../../`、绝对路径逃逸、symlink、Windows 路径分隔符（`\`）、非法/Unicode 文件名——断言文档操作不越出 documents 根；
  2. `external_file_service`：恶意 content:// URI（超长、空、非文件 URI、伪造 scheme）不崩溃、不逃逸；
  3. 导出临时文件：`writeBytesToTempFile` 文件名注入（`../`、路径分隔符、保留名）不逃逸临时目录；
  4. front-matter 解析：畸形 YAML 不崩、不丢内容（单行降级路径复用）；
  5. **Agent 边界预留**：上述 safe-path 校验收敛为单一 `core/utils/safe_path.dart` 纯函数（当前实现散在各 service），未来 Agent tool 层直接复用该函数——测试即为其契约测试；
- **验收**：每条边界有显式用例（含 SoloMD 式真实 exploit 反推用例：`{"path": "../../tmp/x.md"}` 必须被拒）。

### 3.4 U4（P1）：文档完整性不变量（Document Integrity Invariants）常态守门 【学 SoloMD + 已有 ADI 资产】

- **定位升级**：不是"再写几个测试"，而是把测试从**用例集合**升级为**系统不变量集合**——任何状态变化之后，不变量必须全绿；这与 ADI `invariant_checker` 高度同构（ADI 是事后诊断面，本项是事前拦截面，同一套检查逻辑两个消费面）。
- **不变量清单（I1-I9）**：

| # | 不变量 | 生命周期段 |
|---|--------|-----------|
| I1 | AST 必须始终可序列化（任意中间态 → `fromElement` 不抛异常、不丢块） | 序列化回写 |
| I2 | `serialize(parse(md))` 不丢失核心语义（块级结构 + 行内类型保真；已知 4 类边界按 block_serializer docstring 显式豁免登记） | 解析↔序列化 |
| I3 | undo 后文档语义恢复（undo 前后 source 语义等价，live 漂移清空） | 编辑 |
| I4 | redo 后文档语义恢复（对称 I3） | 编辑 |
| I5 | export 后核心内容存在（Code/Math/Image 引用不得静默消失——**"导出代码消失"类 bug 的直接守门**） | 导出 |
| I6 | reload 后文档内容一致（save → 重新 read → parse → AST 语义等价） | 持久化 |
| I7 | code block content 不可静默丢失（任意事务链后 fence 内字节级保真） | 编辑↔导出 |
| I8 | math source 不可静默丢失（公式 latex 原文保真，含 `\` 转义） | 编辑↔导出 |
| I9 | image reference 不可静默丢失（url/alt 保真） | 编辑↔导出 |

- **落地形态**：`test/editing/invariant_gate_test.dart`——不变量检查抽为纯函数（复用 `invariant_checker`），以 L2/L3 语料（U0b）为输入驱动：fuzz 驱动 I1-I4（任意事务序列后断言）、集成驱动 I5-I9（L3 真实样本走 parse→edit→save→export→reload 全链后断言）；
- **验收**：I5-I9 直接对应"导出代码消失"事故；任何"静默丢失"类 bug 报告必须先补对应不变量再用例。

### 3.5 U5（P1）：性能门禁 job 【补 G5，直接服务 issue #245】

- **做法**：仿 golden job 模式：CI 新增 perf job，跑 `flutter test --tags perf`，对 #245/#246/#247 修复后建立**基线阈值**（如：1000 块文档按键 wordCount 更新 < 8ms、首帧解析 < 500ms——数值以修复后实测为准），超阈值即红；
- **验收**：issue #245 修复 PR 必须同时提交阈值基线，防止回归。

### 3.6 U6（P2）：真实编码样本 fixture 集 + 生命周期化断言 【补 G7，学 Jota→UniversalChardet】

- **定位升级**：测试断言从 `decode() 返回某字符串`升级为**完整生命周期语义不丢失**：`fixture → detect/decode → parse → serialize → decode(写回) → 语义等价`——编码问题可能在链路任何一段暴露（decode 对、encode 错、round-trip 丢），单点断言测不到。
- **fixture corpus**（`test/fixtures/encodings/`，进 U0b L3 层）：UTF-8（无 BOM）/ UTF-8 BOM / GBK / GB18030 / Big5 / UTF-16LE / UTF-16BE，每个样本含中文正文 + 一个行内公式 + 一段代码块（让样本同时可驱动 U4 的 I6/I8 不变量）；文件头注释登记来源与许可（自产样本 CC0）；
- **断言形态**：参数化逐 fixture 跑完整链，末态与首态做**语义等价**对比（复用 U4 的 AST 归一化比较），而非字符串全等；
- **时机**：与 §4.2 编码显式化（EXTERNAL-PROJECTS-EMPOWERMENT-PLAN §4.2）同 PR 落地。

### 3.7 U7（P2）：E2E 发布门制度化 【补 G6】

- **做法**：在 docs/engineering/VERIFICATION-POLICY.md 增补"发布前 E2E 必跑清单"（对齐 SoloMD dogfooding 门）：integration_test 全轮 + 真机冒烟 5 项（外部分享打开/公式/Mermaid/导出/自动保存恢复）；CI 可先保持手动触发，发布 tag 时强制。

### 3.8 汇总与排期

| 项 | 优先级 | 工作量 | 依赖 |
|----|-------|--------|------|
| U1 spec 一致性套件 | P0 | 4-5 人日 | §11.1 A1 对拍基建 |
| U2 IME 矩阵 | P0 | 2-3 人日 | 无 |
| U3 安全边界族 | P1 | 2-3 人日 | 无 |
| U4 不变量守门 | P1 | 2-3 人日 | 复用 invariant_checker |
| U5 perf 门禁 | P1 | 1-2 人日 | issue #245 修复先行 |
| U6 编码样本集 | P2 | 1 人日 | 与 §4.2 同 PR |
| U7 E2E 发布门 | P2 | 0.5 人日（文档） | VERIFICATION-POLICY 更新 |
| U9 Export Semantic Snapshot | P0 | 2 人日 | 并入 U4 首个落地场景 |
| U8 Layered Debug Snapshot | P1 | 3-4 人日 | 复用 render_tracer |
| U10 Pixel Region Sampling | P2 | 1-2 人日 | 试点后再定推广 |

合计 16-22 人日。U1/U2 与本文档 §11.5 执行顺序的第二梯队并行；U5 绑定 #245 修复 PR；U9 与 U4 同 PR 优先落地。

### 执行状态（2026-09-12 更新）

| 项 | 状态 | 交付物 |
|----|------|--------|
| U1 | ✅ 已落地（Wave 3，PR #272） | spec 套件 + ratchet 基线 358/652（54.9%），见 COMMONMARK-CONFORMANCE-BASELINE.md |
| U2 | ✅ 已落地（Wave 1，PR #271） | ime_matrix_test.dart（3 locale × 守门/commit/cancel/续行） |
| U3 | ✅ 已落地（Wave 1） | test/security/ + documentPathFor 守门 |
| U4 | ✅ 已落地（Wave 1，随 U9） | export 语义恒等断言（invariant_checker 全量接入待后续） |
| U7 | ✅ 已落地（Wave 1） | VERIFICATION-POLICY.md 发布门清单 |
| U9 | ✅ 已落地（Wave 1+2） | export_semantic_snapshot_test.dart + TXT 加粗丢失修复 |
| U10 | ✅ 试点落地（Wave 2） | pixel_region_sampling_test.dart（3 用例） |
| **U5** | ✅ **已落地（本次）** | perf_ratchet_test.dart（4 指标 ratchet）+ ci.yml perf job + perf_baseline.json；**注意：实际未等 #245 修复先行——ratchet 以当前实测为基线（list 1732ms / parser 38.12ms 等），#245 修复后下调基线固化收益** |
| U6 | ✅ 已落地（本次） | 真实编码样本 fixtures（test/fixtures/encodings/ 6 样本）+ file_service_encoding_fixtures_test.dart（7 用例）；**登记缺口：decodeBytesAuto 容错 UTF-8 永不抛错 → GBK/UTF-16 专属分支不可达，GBK 文件产出 U+FFFD 乱码，待 §4.2 显式编码入口修复** |
| U8 | ✅ 已落地（本次） | render_debug_snapshot.dart（三层 snapshot + contentHash + firstMismatch）+ evidence/layered_snapshot_test.dart（5 用例，AST↔editor-model↔render 三层 hash 恒等）；**登记缺口：嵌套列表 fromElement/toElement round-trip 丢 nested（A4 守门，修复后翻转断言）** |

U5 实测基线（本机 debug JIT，slack ×2-3）：parser 1000 行 38.12ms ｜ 单块 toElement 0.071ms ｜ 整篇 1000 块 220ms ｜ listDocuments 1000 文件 1731.72ms。CI perf job 跑 `--tags perf`（TC-PERF 绝对阈值 + ratchet 双重断言）。

### 3.9 反向启示（不学什么）

- **不学 Markor 的"无 UI 测试"**：我们 golden + widget 测试已是质量资产，作者本人也在 issue #2584 中承认 UI 测试价值，只是维护成本权衡——我们应做的是把易碎断言收敛到 tokens/golden 层，而非删除；
- **不引入 UiAutomator 式重型 E2E**：Flutter patrol 已覆盖，且 AGENTS.md §13 已记录 E2E 超时成本，扩量前先做 U7 制度化；
- **spec.txt 不直接当唯一真源**：我们支持公式/GFM 扩展，spec 套件必须与现有 round-trip fuzz 并行（前者测"符合标准"，后者测"自洽保真"），二者互补不可互替。

---

*文档版本：v1.1（2026-09-11，并入 vgpu 范式迁移分析 §4 与 U8-U10）。分析基线 `8f76f51`。升级项执行均须走 PR 流程；U1 使用的 spec.txt（CC-BY-SA 4.0）与 commonmark-java（Apache 2.0）需在引用处保留许可声明；vgpu（vercel-labs）仅作方法论参照，不作为依赖集成。*
