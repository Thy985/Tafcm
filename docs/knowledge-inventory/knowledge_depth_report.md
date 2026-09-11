# Tafcm 深度知识档案（Evidence-Driven Deep Dossier）

> 本文件是第一轮 Inventory 的**替代产物**。第一轮把 Tafcm 压缩成了"证据优先于声明""契约优先于约定"等通用话术，那是任何规范项目都能说的，不是 Tafcm 的。本档案反过来：**每个知识单元都从项目真实发生的事件、实验、commit 讲起**，先有血肉，后有抽象。
>
> 证据强度标注沿用 S0-S8。所有引用均可溯源到 `docs/decisions/ADR/`、`docs/archive/runs/`、`docs/archive/audits/`、`tools/`、git history。

---

## 单元一 · 范式批判如何变成重构纲领（CRITICAL-REVIEW）

**发生了什么（具体）**
2026-07-18，一份以 Typora 为基准的批判报告对整个 `lib/` 做了 1 小时全量审查，结论极其严厉："这个项目不配称为 Typora 端侧手机版，本质是带公式预览的 Markdown 编辑器原型。" 报告逐条给代码证据：编辑/预览分离（`editor_screen.dart:300-321` 的 `isPreview` 三元）、**三套互不相通的存储**（SharedPreferences + `formula_fix_documents.json` + `formulafix_<ts>.md`，同一段内容可能存三份、互相不同步，用户不知道文档存哪了）、DocumentListScreen 是 240 行死代码无路由、同名 Provider 在 `providers.dart` 和 `editor_providers.dart` 各定义一遍（Riverpod 按 identity 注册，两屏暗色模式可能不同步——隐蔽 bug）、解析器缺 7 类元素但工具栏能插入（"功能性的欺骗"）、每次按键全量解析 1000 行。

**关键数字**：21 项 Typora 核心特性中 0 项完全达成，5 项部分实现，16 项完全缺失或范式错误。按 P0（不修不能称为该产品）/P1（严重影响使用）/P2（影响专业感）/P3（工程化）分 35 项。

**项目怎么做**：不是"修复清单"，而是**范式级裁决**——接受 WYSIWYG 范式重构、收敛单一真相源（`.md` 为唯一真相）、重写解析器。每项 P0 追踪修复 commit（如 P0-2 三套存储 `b43e5c1`、P0-5 Provider 重复 `ec76f06`），报告开头维护"状态更新表"，把已修/未修用 checkbox 形式持续跟踪到 Phase 3.7。

**为什么重要**：这份批判的**知识价值不在结论，而在方法**——它确立了"以外部标杆（Typora）逐条做证据化对照，按严重程度分级，结论可触发范式级决策"的审查模式。项目后续每次大转向（WYSIWYG、验证体系）都能追溯到这份批判的某一条。

**抽象**：当产品被判定"范式错误"时，增量修补无效，必须先裁决范式（接受/拒绝成本），再重构。P0 列表是重构纲领，不是 backlog。

**证据强度 S7（人类确认的范式裁决，后续 Phase 0-3 全部以此为纲领）**。
**迁移**：任何"以为自己在做 X 其实在做 X 的近似品"的产品审查。

---

## 单元二 · 用差分实验逼近一个"看起来查不出根因"的真机卡死（ADR-0032 + Export 专项）

**发生了什么（具体）**
真机导出 PDF 卡在"渲染公式 39/118"不动，进度永久冻结。第一反应是"分片不够细"或"SVG 内容太复杂"。

**项目怎么做**：不猜，做**完整差分实验**：

| 实验 | 操作 | 结果 | 结论 |
|------|------|------|------|
| B-1 | 分片到 30 块/片 | 第一片仍永久卡死 | 分片假设否定 |
| B-2 | 纯 Dart 复现（118 真实 SVG + 手写复杂 SVG） | 全部 1s 内完成 | SVG 内容/解析器死循环排除 |
| B-3 | 真机差分 A/C/C+（30 块 ± 1 公式） | 116-140ms 全部完成 | 字体/大页面/单公式排除 |
| B-3-E | 真机 30 块 + 12 公式 SVG | **addPage 永久卡死** | **多公式 SVG 密度 = blocking primitive**（真机环境特有） |

**关键发现**：`pdf.addPage(MultiPage)` 是同步调用，无法 await/中断，`try/finally` 不会触发 → Export Future 永不进入 terminal state → UI 冻结在最后一次成功帧。**架构性缺陷独立于根因**——即使永远查不出是字体/内存/绘制问题，也不应允许导出无限卡死。

**决策**：addPage Watchdog（超时放弃该页同步布局，降级为公式文本 fallback，导出继续）+ 每页 manifest 诊断 + **"任何 Export Stage 都不得存在无限等待，根因未明也必须能进入 terminal state"作为架构原则**，进入 Export Contract / FFX Capability Contract（新增 `assembly_finite` 检查项）。

**为什么重要**：这展示了"查不出根因时怎么保系统"——不追求根因，追求**有限性保证 + 可诊断性**。替代方案被系统否决：isolate 隔离（dart_pdf 对象不可跨 isolate）、继续缩小分片（B-3 证明非规模问题）、SVG Safety Gate（B-2 证明拦不住真机环境问题）。

**抽象**：同步不可中断的第三方调用 = 信任边界。任何这样的调用都必须外包 watchdog 或迁移出主 isolate，否则 "Future 永不 terminal" 会让整个状态机失效。

**证据强度 S6（真机验证，卡死复现 + watchdog 落地）**。

---

## 单元三 · "Agent 说修好了"如何变成形式化证明（F1-F7 + RUN-007）

**发生了什么（具体）**
Run #006 遗留一个形式化缺口：`validate` 输出 `before=unknown → after=pass`，弱于理想的 `before=reproduced → after=not_reproduced`。也就是说，Agent 只能声称"我没看到错误了"，无法证明"我看到了你那个错误、它确实被修掉了"。

**项目怎么做**：给 `adi.dart` 的 validate 增加 `_deriveBeforeStatus(sessionId)`——遍历 `.adi/observations/*.json`，若该 session 有错误记录则 `before=reproduced`。然后建立 F1-F7 七条件：

```
F1 failure observed        →  .adi/observations 存在（RenderOverflow）
F2 before replay reproduced→  validate.before=reproduced
F3 production patch        →  git diff 可审计（code_block.dart -6 行）
F4 fresh runtime           →  模拟器 integration_test（真实 engine）
F5 after replay not_reproduced → validate.after=pass
F6 invariants pass         →  validate.invariants.allPassed=true
F7 capability regression   →  ffx project create/info 正常
PASS = F1∧F2∧F3∧F4∧F5∧F6∧F7
```

全链路实测：P1 渲染 CodeBlock 触发真实 RenderOverflow → observation 落盘 → Agent 定位 code_block.dart 修复 → 重编译 → replay=not_reproduced → `before=reproduced, after=pass, invariants=true`。

**关键成果**：`reproduced → not_reproduced` 全链路绑定，杜绝 `unknown → pass` 弱断言；F2 修复是纯 CLI 层（adi.dart），不动 Agent harness——验证了 ADI 作为**独立诊断层**的可演进性。

**为什么重要**：这是整个项目最深的一点。当"修复"由 Agent 完成时，人类无法再通过"读代码"判断对错，必须把"修复"拆成**可机械验证的七段证据链**。before 状态绑定（"先复现，再修复"）是核心——没有 before 的 after 毫无意义。

**抽象**：Agent 声明（"我修好了"）在信任体系里等于零，除非它能展示 `reproduced → not_reproduced` 的完整证据链。声明不是证据，复现是。

**证据强度 S7（人工确认 F1-F7 验收，模拟器真实 runtime 验证）**。

---

## 单元四 · "修复成功 ≠ 能力干净"——验证体系的语义精度（RUN-010）

**发生了什么（具体）**
F3 运行时真实缺陷闭环：故意回退 `formula_extractor.dart:98`（latex 截断 → 保真丢失），`ffx capability verify formula` 应声 fail。修复后 `repair-verify` 首次显示 **target_failure=PERSISTENT（误报）**。

**根因**：`formula` 能力有**既有**的 ADI RenderOverflow 观察（Run-004 起 persistent），`no_adi_render_failure=false`。旧判定用 capability 整体 status（after=fail → PERSISTENT），无法区分"本次新增缺陷"和"既有 baseline"。

**修复**：target_failure 改为基于**本次新增 failed checks 的恢复**——`target_checks = before_failed − historical`（历史失败集），全部恢复 → RESOLVED。验证后 `target_failure=RESOLVED`，而 `after=fail` **是正确语义**（既有 ADI 观察仍 fail）。

**为什么重要**：这是验证体系最容易犯的错误——把"能力整体不干净"当成"修复失败"。如果误报，Agent 会陷入"永远修不好一个本来就没说要修的问题"的循环。区分**本次缺陷**与**既有基线**，是任何回归体系的必备精度。

**抽象**：验证系统必须区分"本次变更引入/解决的问题"与"系统既有的问题"。用差集（before_failed − historical）定义 target，而不是用整体状态。

**证据强度 S5（自动化验证 + 人工确认语义修正）**。

---

## 单元五 · 如何验证"看似只能人工判断"的视觉（E8 三层流水线）

**发生了什么（具体）**
"公式渲染得对不对"——长期以来只能靠人眼看。E8 要把它机械化，且不能退化成脆弱的 PNG hash 比较（真机 subpixel/font/GPU/抗锯齿差异会让 hash 必挂）。

**项目怎么做**：建立三层验证流水线：

```
E8.1 Screenshot Integrity   截图存在/PNG 有效/尺寸非空（bytes=4910, 823×168）
E8.2 Structural Fidelity    公式结构解析：E=mc² → {type: superscript, base:'E = mc', sup: '2'}
                            \frac{a}{b} → {type: fraction, numerator:'a', bar:True, denom:'b'}
E8.3 Pixel/Visual Fidelity  pixel diff + 容差（diff_ratio 0.0→pass；改像素 1.0>0.05→fail）
```

**核心洞察**：E8.2 结构解析（Formula AST → Expected Layout Structure → Rendered Structure）**比纯 pixel diff 稳健得多**——它验证"语义结构正确"，不依赖 subpixel/font/GPU。E8.3 用"pixel diff + tolerance"而非"hash 相等"，容忍真实设备的亚像素差异。

**同时**：`evidence_strength` 枚举语义收紧——`Emulator PASS ≠ release gate PASS`。Formula 的 `achieved=['synthetic','virtual_device_runtime']`（模拟器证据）但 `minimum_required='physical_device_runtime'`（release gate 要真机）。防止"模拟器过了→release 过了"的语义偷换。

**诚实边界**：E8 当前用模拟器截图 + 结构解析 + diff 容差，真机截图与完整 SSIM/感知距离管线仍登记 Release Gate。

**为什么重要**：这是"把主观判断机械化但不丢失判断力"的模板。结构层（语义）→ 像素层（外观），层层递进；证据强度按真实性分级，模拟器证据不能冒充真机证据。

**抽象**：验证"视觉正确性"时，优先验证**结构语义**（比像素稳健），像素比较用容差而非 hash；任何验证都要声明证据的"真实性层级"，低层证据不能冒充高层。

**证据强度 S5（自动化验证）+ S7（评审确认语义收紧）**。

---

## 单元六 · 编辑器内核：Transaction、Coalescing 与"意图层"（ADR-0008/0009/0020）

**发生了什么（具体）**
早期编辑器 UI 直接调 `BlockOperations`：用户按 Enter = `split` + `insertAfter` 两步，产生两个 Transaction → Undo 只能撤销一步、中间失败状态不一致。这是"UI 直接操作内核"的经典反例。

**项目怎么做**（三层决策链）：
1. **Transaction = 原子边界**：1 Transaction = 1 Undo 单元，一组可逆 EditOperation（apply 顺序执行 / revert 逆序）。`CommandHandler` 封装多步原子性：`Enter = split + transform + focus next` 一个 Command。
2. **Coalescing 防历史爆炸**：**禁止"每字符一事务"**，采用 typing session 合并（类 VS Code）——连续键入 `hello` = 一个 Transaction（5 个 Insert），Ctrl+Z 一次回退整词。判定条件可注入（7 触发条件 predicate：同 BlockId + offset 连续 + 同 origin keyboard + 500ms 窗口）。paste = 单 Transaction 且**不与** keyboard coalescing（不同 origin undo 独立）。
3. **CommandHandler 中间层（v1.1 修订）**：Command 是用户意图（纯数据、可序列化、可重放、未来协同编辑），Handler 是意图分发器（守卫 + TransactionBuilder 生命周期），**Command 不直接操作 TransactionBuilder**。理由：Command 可序列化 → AI/录制回放/协同；Handler 隔离意图与执行 → 未来插 TransactionExecutor 不破坏 Command 接口。
4. **AST 零污染**：UI 状态（focus/selection）禁止进 `DocumentElement`，单独建模 `BlockViewState` 经 BlockId 关联。序列化 .md 不含 BlockId/Transaction（ADR-0008 §9/§7，内存态）。
5. **接口冻结**：Phase 2.9 先做 UI Architecture Prototype，冻结 BlockEditor API / Transaction / BlockOperations / EditorHistory，Phase 3 UI 变为纯工程实现，无架构决策。

**为什么重要**：编辑器是"看似简单实则全链路耦合"的系统。这三层（意图层/事务层/状态层）的职责分离不是装饰，是**可撤销性、原子性、可序列化**的前提。D6 类型克制原则（新增 Block 类型须由编辑语义驱动，禁 `BlueTextBlock` 这类渲染驱动类型）防止 AST 爆炸。

**抽象**：复杂状态系统里，"用户意图"必须与"执行机制"分离；"编辑动作"必须与"历史记录"分离；"文档内容"必须与"UI 状态"分离。任何混用都会破坏 undo 语义、原子性或可序列化性。

**证据强度 S5（841 tests / 0 regression 基线；TC-ARCH-MODEL-1~5 守门测试固化）**。

---

## 单元七 · 架构规则如何被测试固化（TC-ARCH 守门体系）

**发生了什么（具体）**
架构规则（"presentation 禁读 Document.content""UI 禁直接调 BlockOperations""Block 编辑禁 box border"）如果只写在文档里，必然被违反。Tafcm 把它变成**架构守门测试**：

| 守门 | 规则 | 测试文件 |
|------|------|---------|
| TC-ARCH-MODEL-1 | presentation 禁 `doc.content` 直读 | model_content_gate_test.dart |
| TC-ARCH-MODEL-2 | 禁止 `BlockId(` 接 int 字面量 | block_id_type_test.dart |
| TC-ARCH-MODEL-3 | 编辑操作必须经 TransactionBuilder | transaction_gate_test.dart |
| TC-ARCH-MODEL-4 | 块编辑 decoration 必须 InputBorder.none | block_border_gate_test.dart |
| TC-ARCH-MODEL-5 | Block 类名禁渲染语义词 | block_type_gate_test.dart |

**为什么重要**：这是"文档准入四问"（AGENTS.md）的延伸——架构规范如果不被 CI 强制执行，就只是 wishful thinking。用 grep/静态扫描测试把架构规则变成**可失败的 CI 检查**，规则才真正"活着"。

**抽象**：架构约束应该下沉为可自动执行的守门测试，而不是文档声明。守门测试是"架构即测试、测试即架构"的最小实践。

**证据强度 S5（CI 中作为必过检查）**。

---

## 单元八 · "手写还是用库"用实验回答，不用经验（spike + MIGRATION-SPIKE）

**发生了什么（具体）**
Tafcm 有 8 项手写实现（Markdown 解析 500 行、序列化、Word OOXML 870 行、SVG 公式、块渲染器等），而 Dart 生态有 `markdown` 包、`docx_creator` 等。**关键修正（2026-08-18）**：Parser 是否保留手写"不再是经验判断，而是需实验决策的开放问题"——Phase 3.9 fuzz 找到 3 个真实 bug，恰恰说明手写 Parser 已是需持续维护的复杂基础设施。

**项目怎么做**：设计 A/B 基准（复用 fuzz corpus，含 BUG-1~3 + CommonMark/GFM edge cases），比较 7 维度：解析成功率 / AST 结构等价率 / round-trip 收敛 / GFM 覆盖 / 自定义扩展成本 / 异常降级行为 / 性能。**决策规则**：若标准 parser 解决大部分边界 + Adapter 仅需几百行 → 换；若大量特殊转换 / 失去编辑语义 / 自定义语法越挂越多 → 保留。Word OOXML 因依赖图冲突（xml/archive/image 全家桶升级）标记技术债，用 **Export IR 隔离**保留未来迁移出口。

**为什么重要**："手写 vs 生态"是每个工程都会遇到的决策。Tafcm 的示范是：**把决策从"我认为"变成"实验后的事实"**，并显式记录"何时应该重新评估"。

**抽象**：当手写实现的维护成本开始上升时，"换库"不是立场问题，是实验问题。用代表性语料 + 多维度基准做 A/B，决策规则事先写好。

**证据强度 S5（fuzz 语料 + A/B 基准设计）+ S7（Owner 确认技术债策略）**。

---

## 单元九 · 防止"静默失效"：依赖注入的反面教材（ObservabilityService P0）

**发生了什么（具体）**
可观测系统的 ErrorSnapshotter 用构造参数注入，但生产代码用 `ObservabilityService()` 无参构造 → errorSnapshotter 永远为 null → `captureError()` 空操作 → `snapshot.json` **永远缺失且无人知道**。直到审计才发现。

**根因**：把"应该有默认实现的组件"做成了"可选注入"，默认值恰好是空操作。这是"静默失效"——系统最危险的状态，因为它不报错。

**修复**：改为构造体内自动创建（LIGHT/FULL 模式），外部测试仍可注入 mock。代码注释明确记录了这个 P0 的教训。

**为什么重要**：可观测系统本身如果静默失效，会让"证据链"在源头就断掉——Agent 以为在记录，实际什么都没记录。这直接破坏整个信任体系的根基。

**抽象**：检测/观测/审计组件默认必须有真实实现，"可选"应留给测试注入，而不是默认空操作。任何"默认无操作"的组件都是静默失效的温床。

**证据强度 S3（实现 + 代码注释记录 P0 修复过程）**。

---

## 单元十 · 产品语义冻结：防止页面退化成"第二个 X"（ADR-0018）

**发生了什么（具体）**
PR #93 引入 App Shell 底部 4 Tab，初版有 5 项架构缺陷（Human Owner 评审 1.1-1.5）：HomeScreen 走 provider 而 FileManagerScreen 直读 filesystem（违反唯一边界）；`context.go` 切 Tab 整棵子树重建丢状态；EditorTokens 角色漂移；列表显示 UUID 文件名而非标题；无跨屏刷新。

**项目怎么做**：冻结 5 项决策。其中最独特的是 **Reader 语义冻结**——明确"Reader = 阅读空间，不是文件管理，不是收藏列表"，防止其退化为"第二个 Files 页"：

| Tab | 回答的问题 | 数据源 |
|-----|-----------|--------|
| Home | 我最近在写什么 | documentListProvider（updatedAt） |
| Files | 我的全部文档在哪 | documentListProvider（全量） |
| Reader | 我最近在读什么、读到哪了 | ReadingHistoryRepository（独立数据边界） |

同时冻结"派生 Provider 规则"：documentListProvider 是真相源不是查询终点，派生 Provider 只能从它派生（recentDocuments / earlierDocuments），禁止旁路自建通路；统一 AsyncValue 四态契约（loading/error/data+empty），禁止静默 catch 吞错。

**为什么重要**：产品演进中，每个新页面都可能悄悄变成旧页面的复制品（因为"复用数据源最省事"）。Tafcm 的方法是把"每屏回答什么问题 + 数据边界"冻结成 ADR，用职责差异防退化。

**抽象**：多屏产品的每个页面必须回答"我解决哪个独特问题"，并冻结数据边界；复用的应是真相源，而非页面职责。

**证据强度 S3（决策 + 实施）**。

---

## 认知收敛：Tafcm 真正让人"认识到"了什么

从上面十个单元可以看到，Tafcm 的知识**不是**"一个规范的 Flutter 项目怎么做"，而是：

> **当软件生产从"人写代码"转向"Agent 参与甚至主导代码生产"后，传统的软件工程保障机制需要如何重构。**
>
> Tafcm 的回答是：**把"信任"从"人读代码判断"换成"可机械验证的证据链"。**
> - Agent 说修好了 → 不可信；`reproduced → not_reproduced` 七段证据 → 可信。
> - 模拟器过了 → 不可信；evidence_strength 分级 + release gate 要真机 → 可信。
> - "视觉对了" → 不可信；E8.1 完整性 → E8.2 结构 → E8.3 像素三层 → 可信。
> - "手写更好" → 不可信；A/B 7 维度实验 → 可信。
> - "架构守住了" → 不可信；TC-ARCH 守门测试 → 可信。

这正是用户最初关心的"AI 主导软件工程的信任与验证机制"——但第一轮我只给了抽象原则，这一轮给的是**它们如何被 Tafcm 逐条用实验、用证据、用守门测试逼出来的具体过程**。

---

## 待验证候选（保持 Hypothesis 标记）

- **C-01 差分实验逼近法**：B-1/B-2/B-3 的"排除法逼近 blocking primitive"是否可推广为系统 debug 方法论？当前仅 1 个案例（PDF 卡 28%）。
- **C-02 结构优先视觉验证**：E8.2 结构解析优于 pixel diff 是否普遍成立？当前仅公式渲染 1 类。
- **C-03 语义差集判定**：target_failure = before_failed − historical 是否适用于所有回归体系？当前仅 ffx repair-verify 1 处。
- **C-04 守门测试取代文档规范**：TC-ARCH 守门体系在多大程度上可替代 AGENTS.md 文档？成本收益比未知。
- **C-05 意图层可序列化**：Command 作为协同编辑操作单元（ADR-0009 §协同编辑兼容性）未实现，仅设计意向。

---

*本档案由深度考古生成：30/30 ADR 精读、8 份 audits、31 份 runs、4 份 spikes、核心代码（observability/editing）实现核对、git history 演化追踪。未修改任何仓库资产。*
