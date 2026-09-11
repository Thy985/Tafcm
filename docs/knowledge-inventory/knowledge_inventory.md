# Tafcm Knowledge Inventory

> 只读知识考古产物（Knowledge Archaeology）。本文件不修改仓库任何资产，只做盘点、分级与映射。
> 日期：2026-09-02 · 范围：Tafcm 全仓（1586 有效文件）

## Inventory Summary

- **Repository scope**: Tafcm 全仓（docs / decisions / contracts / regression / evidence / archive / tools / flutter_app lib+test / .github / .agent）
- **Files inspected**: 120+（核心 docs、14 篇精读 ADR、31 篇 ADR 索引、4 篇 principles、8 份 audits、16 篇 phase3.11 runs、7 篇 dogfood runs、8 篇 ADL runs、11 份 contracts、CI workflows、AI_POLICY、AGENTS.md、lib 结构、测试体系）
- **Knowledge objects**: 44（K-001 ~ K-044）
- **High-value objects (A)**: 20
- **B-level objects**: 21
- **C-level objects**: 3
- **Potential cross-project patterns**: 13
- **Potential principles**: 9
- **Decision Patterns**: 9
- **Failure Patterns**: 9
- **Evidence-backed Knowledge**: 28
- **Unverified Candidates**: 8

---

# 知识对象

## A. PRODUCT（产品知识）

---

### K-001 · 范式级批判驱动的产品转向（编辑/预览分离 → WYSIWYG）

**Category**: PRODUCT
**Abstraction**: L3
**Value**: A
**Core Question**: 为什么 Tafcm 从"编辑/预览双模式"彻底转向"块级所见即所得"？
**Problem**: 2026-07-18 前产品是"带公式预览的 Markdown 编辑器原型"，用户在编辑/预览两个视图间反复横跳，每次切换丢失上下文；Typora 的灵魂是编辑即渲染。
**Tafcm Evidence**: `CRITICAL-REVIEW.md` 用代码证据逐条论证范式级缺陷（editor_screen 的 isPreview 三元切换、previewModeProvider 全局状态、预览被卡片包裹等），给出 P0/P1/P2/P3 四级严重度分级；21 项 Typora 核心特性对齐度当时为 0 完全达成。
**Decision**: 接受范式重构成本，用 Phase 3 整轮重写为块级 WYSIWYG（`kEnableNewEditor=true`，移除 `previewModeProvider`），并确立"用户看到的是 Document 而不是 Block"的产品哲学。
**Result**: Phase 3.1-A 完成，六层架构下编辑即渲染；CRITICAL-REVIEW 的 P0 项全部关闭，P1 大部分关闭。
**Insight**: 一份"直言不讳、每个判断带代码证据、按严重度分级"的批判报告，比一打"待改进项清单"更能触发范式级转向；批判的价值在于它给了重构一个不可辩驳的"为什么"。
**Generalization**: 对"照抄竞品功能但错过竞品核心哲学"的产品，最有杠杆的干预是范式级审查（找出"灵魂"，再对照差距），而非逐功能补缺。
**Transferability**: FormulaFix / 任何"功能搬运型"产品 / 产品评审方法论
**Evidence Strength**: S5（已在 Phase 3 全部落地并验证）
**Source**: docs/archive/audits/CRITICAL-REVIEW.md · docs/product/PRODUCT.md · ADR-0031 · AGENTS.md
**Knowledge Status**: Experimentally Validated

---

### K-002 · 五维定位作为命名与叙事框架（Typeset·Agent·CLI·Formula·Markdown）

**Category**: PRODUCT
**Abstraction**: L2
**Value**: B
**Core Question**: 品牌名如何承载并强制表达产品完整能力？
**Problem**: "FormulaFix" 的 "Fix" 带负面语义（修复补救），且只表达公式一维，无法承载排版/Markdown/CLI/Agent 四个实际能力。
**Tafcm Evidence**: ADR-0031 评估确认五维均有真实代码支撑后定名 **Tafcm**（Typeset / Agent-native / CLI-native / Formula-aware / Markdown-first）；每维映射到具体资产（WYSIWYG 双态、ADI、ffx-cli、LaTeX SVG、.md 单一真相源）。
**Decision**: 品牌名 = 可展开的五维能力声明；命名规范分层（L0 显示名 / L1 代码层 / L2 叙事文档）；`applicationId` 发布前锁定（发布后不可变）。
**Insight**: 品牌改名的最佳时机是"发布前、无真实用户"时（applicationId 不可变）；"Fix" 类语义应纳入产品命名评审。
**Generalization**: 产品命名决策应绑定能力证据清单，而非拍脑袋；任何"不可变外部身份"（applicationId / 包名 / 域名）都应在早期锁定。
**Transferability**: 其他产品的品牌与发布策略
**Evidence Strength**: S3（已实施 + 全仓 903 处 import 迁移验证）
**Source**: ADR-0031 · PR #177 / #180
**Knowledge Status**: Validated

---

### K-003 · 功能自洽性检查（工具栏插入的语法，解析器必须认识）

**Category**: PRODUCT
**Abstraction**: L2
**Value**: B
**Core Question**: 为什么"工具栏能插入斜体但预览显示原始 `*text*`"是功能性欺骗？
**Problem**: 工具栏插入 `*斜体*`、`` `code` ``、`~~删除~~`、`[链接](url)`，但解析器不识别 → 用户在预览里看到原始语法字符串。
**Tafcm Evidence**: CRITICAL-REVIEW §3.2 建立了"工具栏按钮 vs 解析器识别"对照表，全部失配；将其定性为"自相矛盾——工具栏的功能在解析器里没有对应实现"。
**Decision**: 工具栏与解析器能力必须双向对齐；解析能力缺失的 7 类元素在 Phase 1.5/1.6 补齐。
**Insight**: UI 暴露的功能与后端能力不一致，比"功能不存在"更具破坏性——它消耗用户信任。
**Generalization**: 任何"入口可触发但内部未实现"的路径都应在交付前做自洽性审计。
**Transferability**: 所有编辑器 / 表单 / 工具产品
**Evidence Strength**: S4（修复后回归测试覆盖）
**Source**: CRITICAL-REVIEW.md §3 · ROADMAP Phase 1.5/1.6
**Knowledge Status**: Validated

---

## B. ARCHITECTURE（架构知识）

---

### K-004 · 六层分层 + 依赖单向 + CI 强制（不只是约定）

**Category**: ARCHITECTURE
**Abstraction**: L3
**Value**: A
**Core Question**: 为什么架构分层必须被测试强制，而不是靠评审口头约定？
**Problem**: 分层架构写进文档后，开发者会"顺手"跨层调用；口头约定无法守门。
**Tafcm Evidence**: 六层 `presentation → providers → domain → data → core → main.dart`，循环依赖零容忍；架构守门由 CI 测试强制（layer_dependency / file_access / provider_uniqueness / file_size，见 test/architecture/ 22 个测试）。
**Decision**: 分层纪律 = 可执行测试，不是文档条款；`core` 禁止反向 import 上层。
**Result**: 架构约定有可重复验证手段；重构 PR 要求 0 业务行为变化。
**Insight**: "架构原则必须可测试"是原则能长期存活的前提——不能被测试的约定会被侵蚀。
**Generalization**: 架构约束（依赖方向、文件规模、命名）应转化为自动检查，写进 CI。
**Transferability**: 任何多模块工程
**Evidence Strength**: S4（CI 架构测试持续通过）
**Source**: docs/architecture/ARCHITECTURE.md · AGENTS.md §1 · architecture-principles.md · test/architecture/
**Knowledge Status**: Test Validated

---

### K-005 · .md 文件作为唯一真相源（三层模型 + 原子写 + 幂等迁移）

**Category**: ARCHITECTURE
**Abstraction**: L3
**Value**: A
**Core Question**: 为什么文档存储必须收敛到单一真相源？
**Problem**: 三套互不相通的存储（SharedPreferences / formula_fix_documents.json / .md 文件）并存，同内容可能同时存在三份副本互不同步——数据丢失级缺陷（CRITICAL-REVIEW §2.1）。
**Tafcm Evidence**: ADR-0003 确立 .md 单一真相源 + 三层模型（内容层 .md / 索引层 / 偏好层），原子写、幂等迁移、front matter 最小集、UUID 文件名；废弃 JSON 文档库与 SharedPreferences 存正文，禁止新增第四套存储。
**Decision**: 内容存 .md 文件；派生缓存（SQLite/FileIndex）需先过 ADR。
**Insight**: 存储收敛决策的触发不是"设计洁癖"，而是真实的数据丢失风险；"单一真相源"本质是降低"哪份数据是对的"的认知成本。
**Generalization**: 任何有多个写入路径的系统，都应先定义唯一权威数据源，再谈缓存与索引。
**Transferability**: FormulaFix / 所有本地存储型 App / 数据迁移项目
**Evidence Strength**: S4（迁移测试 + storage 测试覆盖）
**Source**: ADR-0003 · ADR-0014 · CRITICAL-REVIEW §2.1 · docs/archive/audits
**Knowledge Status**: Test Validated

---

### K-006 · 内容寻址资产命名（sha256 + 引用删除）——缓存一致性的根解法

**Category**: ARCHITECTURE
**Abstraction**: L3
**Value**: B
**Core Question**: 为什么缓存资产命名从 UUID+PNG 升级为 sha256+原格式？
**Problem**: UUID 命名无法感知内容变化，同名覆盖导致缓存脏数据；固定 PNG 格式丢失原始格式信息。
**Tafcm Evidence**: ADR-0014 内容寻址：资产文件名 = sha256(内容) + 原格式；引用计数删除（reference removal）而非物理删除。
**Insight**: 内容寻址让"缓存命中"天然等价于"内容正确"；引用计数把删除决策从"何时删"变成"还有谁引用"。
**Generalization**: 派生资产/缓存系统用内容哈希作键，可免去大量失效与同步逻辑。
**Transferability**: 所有缓存 / 构建产物 / 资产管线
**Evidence Strength**: S3（已实施）
**Source**: ADR-0014
**Knowledge Status**: Implemented

---

### K-007 · Transaction 模型 + Live/Committed 双状态（复杂编辑状态的正解）

**Category**: ARCHITECTURE
**Abstraction**: L3
**Value**: A
**Core Question**: 为什么编辑器要把"文档状态"与"编辑事务"与"历史记录"解耦？
**Problem**: 编辑器有复杂的可变状态：文本、选区、撤销栈、脏标记；若耦合，任一变化都难以推理，且撤销会破坏 Live 渲染状态。
**Tafcm Evidence**: ADR-0008 Transaction 模型（显式 Transaction + 隐式 coalescing、幂等操作约束、非持久化）；ADR-0012 Live/Committed 双状态——Live 态可自由编辑，Committed 态提交进历史，中间有"暂停 → 调度 → 提交"生命周期；E2E 失败（LIVE-EDIT-01）正是触发双态化的真实原因。
**Decision**: 用户操作 → EditorCommand（纯数据可序列化）→ CommandHandler → TransactionBuilder → BlockOperation → AST；编辑/预览分离模式被 WYSIWYG 取代。
**Insight**: "E2E 失败不是 bug，而是架构验证"——一个真实运行失败暴露了状态耦合问题，直接导向双态重构；复杂状态系统的持久状态、变更过程、历史记录不应共享同一职责边界（L4 候选原则）。
**Generalization**: 复杂状态系统应将"当前状态""变更事务""历史记录"分成独立责任面（类似命令模式 + 快照 + 撤销栈分离）。
**Transferability**: 任何富文本/文档编辑器、复杂表单、状态机系统
**Evidence Strength**: S5（E2E + 全量测试验证）
**Source**: ADR-0008 · ADR-0012 · ADR-0019 · E2E/LIVE-EDIT-01 · docs/archive/runs
**Knowledge Status**: Experimentally Validated

---

### K-008 · Renderer 失败不崩溃（用户输入路径上任何层都不能因能力缺失 crash）

**Category**: ARCHITECTURE
**Abstraction**: L3
**Value**: A
**Core Question**: 为什么渲染失败必须降级而不是崩溃？
**Problem**: 公式/图表渲染依赖 WebView 等外部能力，能力演进速度与 Model 层不同步；崩溃 = 用户数据丢失风险。
**Tafcm Evidence**: ADR-0022 Renderer Failure Policy（fallback 降级渲染）；architecture-principles §5（LaTeX→SVG 矢量，flutter_math 降级，绝不 crash；Renderer 不得因未知 BlockElement crash，全量 exhaustive switch）。
**Decision**: 用户输入路径优先保证不崩溃，能力缺失走降级渲染。
**Insight**: 在用户数据路径上，"立即发现错误"是 CI 红灯（好事），但在生产是崩溃（事故）——测试守门与生产行为需要不同策略。
**Generalization**: 用户数据路径的组件应设计"优雅降级"而非"快速失败"；只有开发期才应 fail fast。
**Transferability**: 渲染管线 / 插件系统 / 任何依赖外部能力的 UI
**Evidence Strength**: S4
**Source**: ADR-0022 · architecture-principles.md
**Knowledge Status**: Test Validated

---

### K-009 · 可观测性内建（不是事后补丁）

**Category**: ARCHITECTURE
**Abstraction**: L3
**Value**: A
**Core Question**: 为什么可观测性必须作为架构的一部分，而不是事后加日志？
**Problem**: 复杂编辑器 + AI Agent 协作下，故障难以定位；"复现"成本高。
**Tafcm Evidence**: ADR-0023 Editor Observability System：五层 trace（Interaction/Command/Transaction/Error Snapshot/Replay）+ Canonical AST Fingerprint（确定性序列化）+ Invariant Checker（Layer 0）+ LIGHT/FULL/OFF 三级模式（tree-shaking 移除）+ 隐私默认不含正文 + trace_id/span_id 跨层关联。
**Decision**: 可观测性 = 架构组件；关键行为必须有诊断入口（渲染追踪、错误快照、诊断 zip 导出）。
**Insight**: "复现即测试"——错误快照（类似 crash dump）+ 回放让"能不能复现"变成确定性过程；三级模式解决观测本身的开销与隐私问题。
**Generalization**: 复杂交互系统应把 trace/快照/回放作为一等公民，而非事后日志。
**Transferability**: 复杂编辑器 / Agent 系统 / 需要远程诊断的 App
**Evidence Strength**: S4（observability 测试 32 个文件）
**Source**: ADR-0023 · ADR-0024 · test/observability/
**Knowledge Status**: Test Validated

---

### K-010 · 编辑行为集中裁决（BlockBehaviorResolver）而非散落渲染组件

**Category**: ARCHITECTURE
**Abstraction**: L2
**Value**: B
**Core Question**: 为什么"渲染组件不裁决行为"？
**Problem**: 各 Block 渲染组件各自实现行为裁决 → 规则分散、冲突、难统一（如 IME 行为）。
**Tafcm Evidence**: ADR-0019 Editor Interaction Layer：输入意图层 + BlockBehaviorResolver 集中裁决；IME 三条铁律（不丢字、不吞键、不死锁）、双层 Undo、UTF-16 offset。
**Decision**: 行为规则收敛到单一裁决器，渲染组件只渲染。
**Insight**: 行为与渲染分离，让"规则变更"只改一处，也让规则可单独测试。
**Generalization**: 交互规则应集中，渲染与行为解耦。
**Transferability**: 编辑器 / 游戏 / 表单交互层
**Evidence Strength**: S4
**Source**: ADR-0019
**Knowledge Status**: Test Validated

---

### K-011 · 块级 WYSIWYG：Wrapping 而非 Flattening（嵌套结构不压平）

**Category**: ARCHITECTURE
**Abstraction**: L2
**Value**: B
**Core Question**: 为什么嵌套列表不能"取文本拼行重解析"？
**Problem**: 旧实现把子列表压平成多行字符串再重解析，破坏 AST 层级语义（CRITICAL-REVIEW §3.4）。
**Tafcm Evidence**: ADR-0007 BlockEditor 抽象确立 Wrapping（包裹）而非 Flattening（压平）；Phase 3 重写后 AST 保持真实树形。
**Insight**: 结构丢失的"快捷实现"最终会反噬渲染、撤销、导出等所有下游。
**Generalization**: 数据模型必须保留真实结构语义，任何"压平后重建"都是技术债。
**Transferability**: 任何树形数据结构系统
**Evidence Strength**: S4
**Source**: ADR-0007 · CRITICAL-REVIEW §3.4
**Knowledge Status**: Test Validated

---

## C. ENGINEERING（工程经验）

---

### K-012 · Evidence Strength 分级 + 发布门禁语义（模拟器 ≠ 真机）

**Category**: ENGINEERING
**Abstraction**: L4
**Value**: A
**Core Question**: 如何防止"环境证据"被偷换成"产品证据"？
**Problem**: 模拟器通过 → 认为 release 也会通过；artifact 存在 → 认为 runtime render 正确；real_execution=true → 误当 production_runtime=true。
**Tafcm Evidence**: Evidence Strength 枚举冻结：`synthetic < test_runtime < production_runtime < virtual_device_runtime < physical_device_runtime < visual < human_confirmed`；"artifact 存在 ≠ runtime render ≠ physical render ≠ visual fidelity"；Formula achieved=['synthetic','virtual_device_runtime'] 但 minimum_required='physical_device_runtime'。
**Decision**: 发布门禁以高等级证据为准；Emulator PASS ≠ release gate PASS（防语义偷换）。
**Insight**: 证据等级的语义收紧（virtual_device vs physical_device）是评审过程发现并修正的——语义命名直接影响门禁正确性。
**Generalization**: 任何验证系统都应显式定义证据强度链，并禁止跨等级等价推断。
**Transferability**: 所有质量/发布体系 / CI 门禁设计
**Evidence Strength**: S4（RUN-007/013 冻结 + contracts evidence_strength 字段落地）
**Source**: PHASE3.11-RUN-007 · RUN-013 · testing-principles.md · contracts/*
**Knowledge Status**: Test Validated

---

### K-013 · 能力契约作为机器真相源（contracts/*.json + contract-sync 防漂移）

**Category**: ENGINEERING
**Abstraction**: L3
**Value**: A
**Core Question**: 如何把"功能存在"变成"功能可以被证明"？
**Problem**: 功能完成状态存在文档里（静态表），Agent 无法可计算地验证；文档与代码漂移。
**Tafcm Evidence**: contracts/*.json（11 份）为一等公民机器真相源：required_evidence / required_checks / completion_policy（unknown_max / blocking_unknown / parse_error_max）/ s0_unsupported / evidence_profile；`ffx contract sync` 生成 + schema 校验防漂移。
**Decision**: Feature Capability Matrix 为 contracts 的派生投影，不是反过来的。
**Insight**: "契约先行"让 Agent 与人都能回答"这个能力到底完成没有"，且答案可审计；Re-Audit 曾发现契约矛盾（unknown_max=3 但 s0=5 → verify 误报 fail），证明"契约本身也要被验证"。
**Generalization**: 功能完成度应定义为机器可验证的契约 + 证据链，而非人工勾选。
**Transferability**: Agent 协作项目 / 平台型产品 / 任何"完成度声明"场景
**Evidence Strength**: S4（FULL-CAPABILITY-REAUDIT 全量 ffx verify + contract-sync）
**Source**: contracts/*.json · ADR-0030 · FULL-CAPABILITY-REAUDIT.md · PHASE3.11-RUN-009
**Knowledge Status**: Test Validated

---

### K-014 · Failure Identity 四层（baseline failure set + fingerprint diff）——回归判定

**Category**: ENGINEERING
**Abstraction**: L3
**Value**: B
**Core Question**: 如何区分"既有失败"与"新增回归"？
**Problem**: 冒然把所有失败都当回归会误报；既有失败被忽略会漏报。
**Tafcm Evidence**: testing-principles §3 回归纪律：baseline failure set + fingerprint diff（四层 Failure Identity）；"既有失败 ≠ 新增回归；不得为通过 CI 删除测试"。
**Decision**: 回归判定基于可计算的基线差异，而非人工判断。
**Insight**: 失败指纹化让"回归检测"从直觉变成可审计的 diff。
**Generalization**: 测试维护中，应先建立基线失败集，再谈增量回归。
**Transferability**: 所有 CI / 回归体系
**Evidence Strength**: S4
**Source**: testing-principles.md · VERIFICATION-POLICY.md · PHASE3.11-RUN-003
**Knowledge Status**: Test Validated

---

### K-015 · Golden 基线跨平台限制 + CI 镜像固定防漂移

**Category**: ENGINEERING
**Abstraction**: L2
**Value**: B
**Core Question**: 为什么 golden 测试不能跨平台直接比对？为什么 CI 镜像要固定版本？
**Problem**: 跨平台字体差异导致同一渲染在不同 OS 产生不同像素；ubuntu-latest 浮动镜像升级会静默改变渲染基线（GOLDEN-CI-001 根因）。
**Tafcm Evidence**: testing-principles：golden 基线 Linux CI 生成，Windows 本地不比对；ci.yml 固定 `CI_IMAGE: ubuntu-24.04`（Tier 2 固定镜像杜绝漂移）；改基线走 update_goldens workflow（workflow_dispatch 一键完成）。
**Decision**: 视觉基线绑定到确定性环境；基线更新是显式动作。
**Insight**: 视觉验证的敌人是环境不确定性；固定镜像 + 显式基线更新，把"视觉漂移"从隐性变为可控。
**Generalization**: 任何视觉/快照测试都应固定渲染环境，并把基线更新做成显式门禁。
**Transferability**: 视觉回归 / 快照测试 / CI 设计
**Evidence Strength**: S4
**Source**: testing-principles.md · .github/workflows/ci.yml · GOLDEN-CI-001
**Knowledge Status**: Test Validated

---

### K-016 · 静态状态污染测试（static cache 跨用例共享）

**Category**: ENGINEERING
**Abstraction**: L2
**Value**: B
**Core Question**: 为什么 static 缓存/字体状态是测试污染源？
**Problem**: `PdfExporter._cjkFont`、`FormulaSvgService._cache`、`MermaidService._cache` 为 static，跨测试共享；测试 A 触发加载失败 → 30 秒内测试 B 拿不到字体。
**Tafcm Evidence**: CRITICAL-REVIEW §8.5 定性；部分清理（加 clearCache()），`_cjkFont` 仍 static 为已知债。
**Insight**: 可测性要求状态注入而非全局静态；静态状态在测试里表现为"顺序依赖的幽灵失败"。
**Generalization**: 全局可变状态与可测试性互斥；服务状态应可重置/可注入。
**Transferability**: 所有可测试性工程
**Evidence Strength**: S3（部分修复）
**Source**: CRITICAL-REVIEW §8.5 · testing-principles §5
**Knowledge Status**: Partially Resolved

---

### K-017 · 每次按键全量重算的性能教训

**Category**: ENGINEERING
**Abstraction**: L2
**Value**: B
**Core Question**: 为什么"每按一个键全量解析整篇文档"不可行？
**Problem**: 文档 1000 行时每个字符输入都遍历 1000 行 + 重建所有 Widget；WebView 公式渲染每条 30s 超时、并发 4、整体导出 120s 超时。
**Tafcm Evidence**: CRITICAL-REVIEW §5.1/5.3 量化（100/4×30s=12.5min，>16 个未缓存公式导出必失败）；Phase 3 后块级增量渲染。
**Insight**: 全量重算的代价随文档规模线性膨胀；块级增量是关键。
**Generalization**: 交互热路径必须增量计算，全量重算只能出现在"非交互"动作。
**Transferability**: 编辑器 / 渲染引擎 / 大数据列表
**Evidence Strength**: S5（Phase 3 后性能验证）
**Source**: CRITICAL-REVIEW §5 · ROADMAP Phase 3
**Knowledge Status**: Validated

---

## D. AGENT（Agent 工程知识）—— Tafcm 最独特的知识域

---

### K-018 · AI 权限矩阵 + Human Owner 边界（AI 是助手不是 Owner）

**Category**: AGENT
**Abstraction**: L3
**Value**: A
**Core Question**: AI Agent 在工程系统中应拥有什么权限？
**Problem**: 无边界授权 → AI 越权合并、改 CI、删历史，不可逆；或反之过度限制 AI 无法干活。
**Tafcm Evidence**: AI_POLICY.md 权限矩阵：AI 可创建分支/提交/推送/建 PR（commit 必须含 Task scope）；合并 main / 修改 CI / 修改 AGENTS.md / 删分支历史 = Human 专属；ADR/数据模型/新依赖 = AI 提案、Human 批准。AGENTS.md §6.4 Human-Owner 文件（ADR/ARCHITECTURE/ROADMAP）AI 不代签。
**Decision**: 权限按"可逆性 + 架构影响"分级；架构决策类文件 AI 永不经自 merged。
**Insight**: 权限设计的关键不是"AI 能力多强"，而是"哪些操作不可逆/影响架构 → 必须 Human"。
**Generalization**: Agent 系统的权限矩阵应以"操作的可逆性与架构影响"为维度设计。
**Transferability**: 所有 AI 协作工程 / 自建 Agent 平台
**Evidence Strength**: S5（长期执行 + 8 次 ADL 闭环验证）
**Source**: .agent/AI_POLICY.md · AGENTS.md · ADR-0025
**Knowledge Status**: Runtime Validated

---

### K-019 · Untrusted Analyzer 三段式（AI 提供判断，系统掌握权力）

**Category**: AGENT
**Abstraction**: L4
**Value**: A
**Core Question**: 在公开仓库（不可信输入）里，如何让 AI 参与决策而不放大安全风险？
**Problem**: PR 来源不可信，prompt injection 可把"LLM 输出错误"放大为"仓库授权滥用"；输入源与执行权限不能在同一信任域。
**Tafcm Evidence**: ADR-0025 三段式：`Deterministic Extractor（fetch_input.sh，规范化 context.md）→ AI Reasoning Layer（claude-code-action，仅写 findings.json，无写权限）→ Deterministic Executor（create_issues.sh，白名单校验 + 建 Issue）`；Claude 的 --allowedTools 仅 Read/Glob/Grep/Write(限 findings.json)，禁止 gh/写 API。
**Decision**: AI 输出永远只是"建议"，由确定性脚本按契约校验后才可能落地为副作用；job 级 permissions 物理隔离读写（analyze job 无任何写权限）。
**Insight**: "AI 提供判断，系统掌握权力"——把 LLM 从"执行者"降级为"分析器"，注入面被确定性格挡。
**Generalization**: 任何公开/低信任输入的 AI 自动化，都应采用 提取→分析→执行 三段式，AI 段零写权限。
**Transferability**: GitHub/论坛爬取、客服自动化工单、内容审核——所有"不可信输入 + AI + 副作用"系统
**Evidence Strength**: S4（fixture 测试 + dry-run 校准）
**Source**: ADR-0025 · .github/workflows/issue-triage.yml
**Knowledge Status**: Implemented + Test Validated

---

### K-020 · ADI：Agent Diagnostic Interface（为 Agent 设计的可观测性）

**Category**: AGENT
**Abstraction**: L3
**Value**: A
**Core Question**: 可观测性如何从"给人看"升级为"给 Agent 用"？
**Problem**: 日志/监控是给人读的，Agent 无法结构化消费；Agent 无法区分"没有 bug"和"诊断坏了"。
**Tafcm Evidence**: ADR-0024 ADI：三层模型（ErrorSnapshot / AdiRecord / AdiView）；Failure Identity（errorType+stackHash 聚合去重）；6 条 Core Principles（Query first / Inspect before edit / Replay before modify / Validate after modify / Never trust candidate_causes / Respect invariant report）；权限模型（readonly/diagnostic/repair）；`adi doctor` 自检区分"无 bug"与"ADI 坏"；Agent Evaluation Loop 记录 Agent 修复尝试。
**Decision**: 把诊断做成 Agent 可查询、可回放、可验证的接口（Runtime Interface 而非调试工具）。
**Insight**: "Never trust candidate_causes"——Agent 的病因猜测必须用数据验证；Replay 把"能不能复现"确定性化。
**Generalization**: Agent 化的系统应提供结构化的诊断接口（查询/回放/验证），而非纯日志。
**Transferability**: Agent 协作工程 / 可诊断产品 / AI 运维
**Evidence Strength**: S4-S5（8 次 ADL 闭环 + dogfood 真实修复）
**Source**: ADR-0024 · docs/archive/runs/adl/* · dogfood/*
**Knowledge Status**: Runtime Validated

---

### K-021 · 置信度三态 + 错误成本不对称（少建成本低，多建污染大）

**Category**: AGENT
**Abstraction**: L3
**Value**: A
**Core Question**: AI 自动决策的阈值如何设计？
**Problem**: 单阈值无法区分错误成本：少建一个 Issue 成本低，多建一个垃圾 Issue 污染仓库。
**Tafcm Evidence**: ADR-0025 D5 置信度三态：≥0.8 High 自动创建 / [0.5,0.8) Medium 仅建议 / <0.5 Low 丢弃；阈值可调；首版 dry_run=true 人工校准。
**Insight**: 自动化的阈值应由"两类错误的相对成本"决定，而非单一准确率。
**Generalization**: 任何 AI 自动化（发邮件、建工单、改配置）都应按错误成本设计三态/分级策略。
**Transferability**: 自动化运维 / 客服工单 / 内容审核
**Evidence Strength**: S4
**Source**: ADR-0025
**Knowledge Status**: Implemented

---

### K-022 · Agent Memory Distillation（Agent 记忆默认 ephemeral）

**Category**: AGENT
**Abstraction**: L3
**Value**: A
**Core Question**: Agent 的过程记忆哪些值得留存？
**Problem**: session 日志、调试笔记、临时决策堆积成"过程垃圾场"，污染文档可信度。
**Tafcm Evidence**: agent-collaboration.md §6 Memory Distillation：已无效→删除；有独立历史研究价值（罕见真机复现/环境事故）→ archive + frontmatter；沉淀为长期知识→提炼进 principles/ADR/guides；"Agent 曾经这么想过"→不保存。
**Decision**: Agent Memory 默认 ephemeral；运行时状态（.agent/state、.adi、.ffx）始终 gitignored。
**Insight**: 知识库的可信度取决于"什么没被保存"；归档入口（archive）是稀缺资源的保护阀。
**Generalization**: Agent 系统应显式定义记忆蒸馏管道，防止过程数据冒充知识。
**Transferability**: Agent 协作项目 / 个人知识库 / 团队 wiki
**Evidence Strength**: S5（长期执行）
**Source**: agent-collaboration.md §6 · AGENTS.md
**Knowledge Status**: Runtime Validated

---

### K-023 · FFX Verification Orchestrator（Agent-Native Verification Harness）

**Category**: AGENT
**Abstraction**: L4
**Value**: A
**Core Question**: Agent 如何"发现、执行、观察、验证"一个系统的能力？
**Problem**: 测试工具平铺命令，Agent 无法把"测试"变成"验证闭环"；验证证据链断裂。
**Tafcm Evidence**: ADR-0030 FFX：5 边界（Orchestrator 能力无关 / Capability Adapter Registry / Runtime Bridge 直调 Dart 生产类 / Artifact Producer / Consumer Adapter）；7 条不变量（FFX 只编排不实现、失败必须真实 diagnostic_id、Evidence > Agent 自述、Consumer 与 Product Runtime 不同证据层、ENV_MISSING≠FAIL、Completion 由 Contract+Evidence 决定、verify/diagnose 只读 repair-verify 只验证不修）；五级退出码 0/1/2/3/127。
**Decision**: "功能完成"从静态表变为可执行协议；Agent 获得可计算、可审计的工程状态。
**Insight**: 验证编排的核心不变量是"谁证明、用什么证明、证明到什么等级"；环境缺失（127）与产品失败（1）必须区分，否则 Agent 会误判。
**Generalization**: 给 Agent 用的验证层应封装为"发现-执行-观察-验证"的协议，而非暴露命令。
**Transferability**: Agent 协作工程 / 测试平台 / 任何 Agent 可编程系统
**Evidence Strength**: S4（FULL-CAPABILITY-REAUDIT 11 能力 ffx verify）
**Source**: ADR-0030 · FFX.md · tools/ffx-cli
**Knowledge Status**: Test Validated

---

### K-024 · 停止条件与升级路径（反复失败 >5 次请 Human）

**Category**: AGENT
**Abstraction**: L2
**Value**: B
**Core Question**: Agent 何时应该停下请求人类？
**Problem**: Agent 无限制重试会烧时间、扩大改动、掩盖问题。
**Tafcm Evidence**: agent-collaboration.md §4 停止条件：Scope 扩大 / 需要新 ADR / 影响超预期 / 与设计冲突 / 同一任务修复 >5 次未过 CI → 停下请 Human；升级路径按问题类型（业务→ROADMAP、架构→ADR、API→dartdoc、测试→principles）。
**Decision**: 停止条件作为行为协议显式写死。
**Insight**: 好的 Agent 协议定义"何时不做"，比"如何做"更能保护项目。
**Generalization**: Agent 自动化应有显式熔断与升级路径。
**Transferability**: 所有 Agent 协作规范
**Evidence Strength**: S5（长期执行）
**Source**: agent-collaboration.md §4-5
**Knowledge Status**: Runtime Validated

---

### K-025 · Agent 故障归因协议（agent-failure-log：Observed Reality > Agent Inference）

**Category**: AGENT
**Abstraction**: L3
**Value**: A
**Core Question**: 当 Agent 与系统判断冲突时，以谁为准？如何归因 AI 故障？
**Problem**: Agent 的自我归因（"我修好了"）不可信；AI 故障需要结构化记录。
**Tafcm Evidence**: ADR-0021 D6 故障归因协议 L0-L3 分级 + agent-failure-log（Agent Failure Dataset）；风险分级 R0-R3；Human Override Principle；"Observed Reality > Agent Inference"；Hard Rule 100% 机器化 + Rule→Test→Gate 流水线。
**Insight**: AI 故障应像软件缺陷一样有数据集、分级与复盘；"硬规则必须 100% 可机器验证"杜绝了"规则执行不彻底"。
**Generalization**: Agent 系统的规则应有测试与门禁，Agent 故障应有日志与归因协议。
**Transferability**: Agent 治理 / AI 运维 / 自动化平台
**Evidence Strength**: S4
**Source**: ADR-0021 · .agent/
**Knowledge Status**: Implemented

---

### K-026 · AI 的 Git 操作权限模型（Agent 提交纪律）

**Category**: AGENT
**Abstraction**: L2
**Value**: B
**Core Question**: AI 的 Git 操作应受什么纪律约束？
**Problem**: AI 提交可能冒充身份、force push、夹带未说明改动。
**Tafcm Evidence**: ADR-0021 D5 / AI_POLICY：Conventional Commits + Task scope；禁止 force push；禁止冒充 Human git 身份；分支从 main 切出；PR 描述与改动范围一致。
**Insight**: Git 历史是"可审计性"资产，AI 的提交纪律 = 可追溯性。
**Generalization**: 任何 AI 写代码的系统都应强制提交溯源。
**Transferability**: AI 协作工程 / 合规审计
**Evidence Strength**: S5
**Source**: ADR-0021 · .agent/GIT_POLICY.md
**Knowledge Status**: Runtime Validated

---

## E. VERIFICATION（验证与评估知识）

---

### K-027 · 如何验证"看似只能人工判断的能力"（E8 三层视觉保真）

**Category**: VERIFICATION
**Abstraction**: L4
**Value**: A
**Core Question**: 视觉/行为这类"主观"能力，如何自动化验证？
**Problem**: 渲染"对不对"、公式"好不好看"传统上只能肉眼验收；肉眼 = 不可重复证据。
**Tafcm Evidence**: E8 Visual Fidelity Pipeline 三层：E8.1 Screenshot Integrity（存在/PNG 有效/尺寸/非空）→ E8.2 Structural Fidelity（从截图解析公式结构，如 `E=mc^2` → superscript 结构，比 pixel diff 稳健）→ E8.3 Pixel/Visual Fidelity（顶层像素/VLM 判定）；test/architecture 22 个架构测试、golden 15 个、E2E patrol。
**Decision**: 把"视觉"拆成 完整性→结构→像素 三层，逐层自动化，人工只兜底顶层。
**Insight**: 结构保真（结构断言）是视觉验证的甜点——比纯像素稳健、比人工可重复；"如何把主观判断结构化"是验证体系的核心问题。
**Generalization**: 视觉/音频/行为验证应先做"结构层"（可解析的中间表示），再谈像素/感知层。
**Transferability**: 渲染引擎 / 设计系统 / 任何视觉质量验证
**Evidence Strength**: S5（模拟器实际运行 + 截图管线）
**Source**: PHASE3.11-RUN-013/014/015/016 · E2E patrol · test/golden
**Knowledge Status**: Runtime Validated

---

### K-028 · Real Defect Repair Loop vs Synthetic Failure Loop（验证循环的真假）

**Category**: VERIFICATION
**Abstraction**: L3
**Value**: A
**Core Question**: 验证循环到底验证了什么？
**Problem**: 注入观察再移除（synthetic loop）可能只是"剧本演练"，没有验证真实修复能力。
**Tafcm Evidence**: RUN-007 区分：Formula Run-004 = Synthetic Failure Loop（注入观察→移除）；PDF = Real Defect Repair Loop（回退真实产品代码 `sanitizeSvgString` 空输入分支 `return input`→`return 'x'`，真实代码缺陷非注入）→ 完整 Golden Loop（verify→diagnose→repair-verify→evidence delta→regression）。
**Decision**: 验证循环的"真实缺陷"维度与"架构泛化"维度分开评估，不把"初步实证"误报为"已证明"。
**Insight**: 验证体系要自证其验证能力——"能不能修真实缺陷"与"能不能跑通流程"是两个不同的主张。
**Generalization**: 任何验证框架都应包含"真实缺陷注入"的基准测试。
**Transferability**: 测试框架 / Agent 评估 / CI 自检
**Evidence Strength**: S5（PDF 真实缺陷完整闭环）
**Source**: PHASE3.11-RUN-007 · RUN-004
**Knowledge Status**: Runtime Validated

---

### K-029 · 消费端验证与产品运行时是不同证据层

**Category**: VERIFICATION
**Abstraction**: L3
**Value**: B
**Core Question**: 产物生成成功 = 功能正确吗？
**Problem**: Word 导出产物存在 ≠ 公式在 Word 里显示正确；消费端（WPS/OfficeCLI）验证不能替代产品运行时验证。
**Tafcm Evidence**: ADR-0030 不变量 4（Artifact Consumer 与 Product Runtime 是不同证据层）；word contract formula_fidelity 字段——docx 内部 latex fallback 必须出现在消费端文本（产物成功≠功能正确，DOGFOOD-RUN-004 修复后字段）。
**Insight**: "产物成功"只是最低证据，功能正确需要消费端闭环。
**Generalization**: 导出/生成类功能应同时验证产物完整性与消费端语义保真。
**Transferability**: 导出管线 / 编译产物 / 数据流水线
**Evidence Strength**: S4-S5
**Source**: ADR-0030 · contracts/word_export.json · DOGFOOD-RUN-004
**Knowledge Status**: Runtime Validated

---

### K-030 · 环境缺失 ≠ 产品失败（127 独立退出码）

**Category**: VERIFICATION
**Abstraction**: L3
**Value**: A
**Core Question**: 如何防止 Agent 把"环境没装"误判为"产品坏了"？
**Problem**: wpscli 未装 → Agent 报告"Word Export broken"；环境依赖混淆于产品缺陷。
**Tafcm Evidence**: FFX 五级退出码 0/1/2/3/127（127 = ENV_MISSING）；ADR-0030 不变量 5。
**Decision**: 环境缺失与产品失败用退出码物理区分。
**Insight**: 验证系统的错误分类决定 Agent 的诊断方向；分类错则归因错。
**Generalization**: 任何依赖外部环境的验证系统都应区分"环境问题/产品问题/证据不足"。
**Transferability**: 测试平台 / CI / 运维告警
**Evidence Strength**: S4
**Source**: ADR-0030 · FFX.md
**Knowledge Status**: Test Validated

---

### K-031 · 通过"真机 + 截图 + 结构断言"达成 physical/visual 证据

**Category**: VERIFICATION
**Abstraction**: L3
**Value**: B
**Core Question**: 如何在无真人监督下拿到 physical/visual 级证据？
**Problem**: release gate 要求 physical_device_runtime / visual 证据，但人工不可重复。
**Tafcm Evidence**: E6 runner（模拟器/真机编排，RUN-012）+ E8 截图管线（scoped storage 问题 → 应用私有目录 /data/data/.../files/）+ E8.2 结构断言；真机 patrol E2E。
**Insight**: 把"真机验证"从人工操作变成可编排的 runner + 证据收集器。
**Generalization**: 移动端验证应把设备编排、截图采集、结构断言做成管线。
**Transferability**: 移动 App / 设备农场
**Evidence Strength**: S5（E6 真机运行）
**Source**: PHASE3.11-RUN-012/013 · E2E patrol
**Knowledge Status**: Runtime Validated

---

## F. DESIGN（设计知识）

---

### K-032 · 沉浸式 vs 卡片包裹（手机端内容哲学）

**Category**: DESIGN
**Abstraction**: L2
**Value**: B
**Core Question**: 为什么预览内容被卡片包裹是反沉浸式？
**Problem**: 手机宽 360-414px，卡片单边 32px 浪费，正文区只剩 ~300px。
**Tafcm Evidence**: CRITICAL-REVIEW §1.2：预览被 Container(16px margin + 12px radius + shadow) 包裹；Typora 全屏沉浸。
**Insight**: 移动端排版工具的正文区是稀缺资源，任何装饰性包裹都是成本。
**Generalization**: 内容型 App 应优先全屏沉浸，装饰降级。
**Transferability**: 阅读器 / 编辑器 / 内容 App
**Evidence Strength**: S5（Phase 3 修复）
**Source**: CRITICAL-REVIEW §1.2
**Knowledge Status**: Validated

---

### K-033 · 错误消息"人话"原则（不透传技术 detail）

**Category**: DESIGN
**Abstraction**: L2
**Value**: B
**Core Question**: 为什么 SnackBar 不该显示 `Unexpected extension byte (at offset 1)`？
**Problem**: 用户看到开发者的技术 detail（栈、offset、source 片段）；技术术语（"WebView 渲染卡死"）破坏信任。
**Tafcm Evidence**: CRITICAL-REVIEW §7.1/7.2：错误 detail 被透传；修复后按用户语言分级。
**Insight**: 错误消息的语言边界 = 用户/开发者职责边界；detail 该进日志不该进 UI。
**Generalization**: UI 错误消息应分层（用户可行动信息 vs 技术诊断），技术信息走诊断通道。
**Transferability**: 所有产品 UI
**Evidence Strength**: S4
**Source**: CRITICAL-REVIEW §7
**Knowledge Status**: Validated

---

### K-034 · 状态管理决策树（Riverpod 选择规则）

**Category**: DESIGN
**Abstraction**: L2
**Value**: B
**Core Question**: 何时用 AsyncNotifierProvider / StateNotifierProvider / Provider？
**Problem**: Provider 乱用导致异步状态无解、状态可变、资源泄漏、同名 Provider 重复定义（CRITICAL-REVIEW §2.4 隐蔽 bug）。
**Tafcm Evidence**: architecture-principles §4 决策树：需异步→FutureProvider/AsyncNotifierProvider；需改状态→StateNotifier/StateProvider；否则→Provider；状态不可变（copyWith）；资源持有型必须 autoDispose；禁止同名 Provider（CI 架构测试强制）。
**Insight**: 状态管理的选择应可规则化（决策树），同名 Provider 的隐蔽 bug 说明"约定必须测试强制"。
**Generalization**: 状态管理选型应沉淀为决策树并进入代码评审。
**Transferability**: 任何 Flutter/Riverpod 工程
**Evidence Strength**: S4
**Source**: architecture-principles.md · CRITICAL-REVIEW §2.4
**Knowledge Status**: Test Validated

---

## G. FAILURE（失败经验）

---

### K-035 · 多套存储并存的隐性数据丢失（三套存储互不相通）

**Category**: FAILURE
**Abstraction**: L3
**Value**: A
**Core Question**: 为什么"三套存储"是数据丢失级缺陷？
**Problem**: 同一文档内容可能同时存在于 SharedPreferences + JSON + .md，编辑器保存不更新文档库 → 用户不知道文档存哪。
**Tafcm Evidence**: CRITICAL-REVIEW §2.1（三套存储对照表，写入方/读取方/位置 + 影响）；触发 ADR-0003 单一真相源。
**Insight**: 多存储并存时，"用户数据到底在哪"不可知，比"缺某个功能"严重得多；这是最先被修的地基问题。
**Generalization**: 任何系统新增存储/缓存前，先问"真相源是谁"。
**Transferability**: 数据架构 / 迁移工程
**Evidence Strength**: S5（修复 + storage 测试）
**Source**: CRITICAL-REVIEW §2.1 · ADR-0003
**Knowledge Status**: Resolved

---

### K-036 · 全局 Provider 重复定义的隐蔽 bug

**Category**: FAILURE
**Abstraction**: L2
**Value**: B
**Core Question**: 为什么同名 Provider 在不同文件是"两个独立实例"？
**Problem**: 两个屏幕的暗色模式可能不同步（一个 import editor_providers.dart，一个 import providers.dart），运行时无报错。
**Tafcm Evidence**: CRITICAL-REVIEW §2.4：Riverpod 按 identity 注册，同名 = 两个实例；CI provider_uniqueness 测试强制修复。
**Insight**: 依赖注入框架的"身份唯一性"约束必须测试强制，否则是幽灵 bug。
**Generalization**: 全局单例/Provider 的唯一性应纳入架构测试。
**Transferability**: Riverpod/DI 工程
**Evidence Strength**: S4
**Source**: CRITICAL-REVIEW §2.4 · test/architecture/
**Knowledge Status**: Resolved

---

### K-037 · GBK 编码兜底（中国用户 .md 的现实）

**Category**: FAILURE
**Abstraction**: L2
**Value**: B
**Core Question**: 为什么外部 .md 字节流不能直接 utf8.decode？
**Problem**: 中国用户历史 .md 常含 GBK 字节，直接 UTF-8 解码崩/乱码。
**Tafcm Evidence**: architecture-principles §2：`decodeBytesAuto` 兜底；file 相关测试覆盖（file_service_decode_test.dart）。
**Insight**: "标准"编码假设会被真实用户生态打破；解码要自动探测兜底。
**Generalization**: 处理外部用户文件的系统必须做编码探测/兜底。
**Transferability**: 文件导入 / 文本处理
**Evidence Strength**: S4
**Source**: architecture-principles.md · file_service_decode_test.dart
**Knowledge Status**: Test Validated

---

### K-038 · scoped storage 权限坑（/sdcard 不可写 → 应用私有目录）

**Category**: FAILURE
**Abstraction**: L1
**Value**: C
**Core Question**: 为什么 Android 截图/文件写 /sdcard 失败？
**Problem**: E8 截图管线发现 /sdcard 与 Android/data 均无写权限（scoped storage errno 1/13）。
**Tafcm Evidence**: RUN-013：改用应用内部私有目录 /data/data/.../files/（应用可写）。
**Insight**: 移动端验证管线要预判 scoped storage 限制。
**Generalization**: Android 文件写入应直接用应用私有目录或 MediaStore。
**Transferability**: Android 开发
**Evidence Strength**: S5（真机修复）
**Source**: PHASE3.11-RUN-013
**Knowledge Status**: Resolved

---

### K-039 · 契约内部矛盾导致 verify 误报（unknown_max 未同步）

**Category**: FAILURE
**Abstraction**: L2
**Value**: C
**Core Question**: 为什么 roundtrip 1.0 的 markdown 能力会被 verify 判 fail？
**Problem**: contract-sync 补 s0 到 5 项后，completion_policy.unknown_max=3 未同步 → 5>3 → 误报 fail。
**Tafcm Evidence**: FULL-CAPABILITY-REAUDIT §3：修复 unknown_max 与 s0 对齐。
**Insight**: 机器验证系统自身也有"契约漂移"问题；契约必须可同步、可验证。
**Generalization**: 元验证（验证验证系统）是必要的一层。
**Transferability**: 契约驱动开发
**Evidence Strength**: S3
**Source**: FULL-CAPABILITY-REAUDIT.md · RUN-009
**Knowledge Status**: Resolved

---

### K-040 · 静默吞异常 → 假"空状态"

**Category**: FAILURE
**Abstraction**: L2
**Value**: B
**Core Question**: 为什么 `catch (_) {}` 静默是坏实践？
**Problem**: 文件加载 IO 出错被吞 → UI 显示"暂无保存的文档"，用户以为真没文档。
**Tafcm Evidence**: CRITICAL-REVIEW §7.3：静默 catch 将错误伪装成空状态。
**Insight**: 空状态与错误状态的 UI 相同 = 用户被误导；异常必须区分"真的空"与"读不出来"。
**Generalization**: 错误与空要区分呈现；静默 catch 只应在明确无害处。
**Transferability**: 所有 UI/IO 层
**Evidence Strength**: S4
**Source**: CRITICAL-REVIEW §7.3
**Knowledge Status**: Resolved

---

### K-041 · 单条公式 30s 超时 × 并发 4 = 导出必然失败

**Category**: FAILURE
**Abstraction**: L2
**Value**: C
**Core Question**: 为什么导出含 16 个以上公式的文档必然失败？
**Problem**: 公式渲染 30s/条 × 并发 4，整体导出 120s 超时 → 100 公式需 12.5min，>16 未缓存即超时。
**Tafcm Evidence**: CRITICAL-REVIEW §5.3 量化推导。
**Insight**: 时间预算的乘积陷阱——单条耗时 × 数量 必须整体建模。
**Generalization**: 批处理性能预算要按"单条×规模"建模，而非只看单条。
**Transferability**: 批处理 / 导出管线
**Evidence Strength**: S5（修复后验证）
**Source**: CRITICAL-REVIEW §5.3
**Knowledge Status**: Resolved

---

## H. METHODOLOGY（方法论）

---

### K-042 · 证据链驱动的能力验证闭环（Capability Verification Pattern）

**Category**: METHODOLOGY
**Abstraction**: L3
**Value**: A
**Core Question**: Tafcm 如何把"功能存在"变成"功能可以被证明"（闭环）？
**Problem**: 功能完成是静态声明，无法被 Agent/机器验证。
**Tafcm Evidence**: 闭环：`contracts/*.json（机器契约）→ ffx verify（执行）→ Evidence Strength 分级 → FULL-CAPABILITY-REAUDIT（11 能力可审计状态）→ 回归/evidence 资产 → Release Gate`；每条证据链：Knowledge → Source → Implementation → Test → Runtime → Human Confirmation（见 evidence_map.md）。
**Decision**: 能力完成 = 契约 + 证据 + 门禁，三者闭环。
**Insight**: 验证闭环的价值在于"可计算、可审计、可复现"的工程状态，取代人工宣称。
**Generalization**: 平台/产品完成度应做成"契约-执行-证据-门禁"闭环。
**Transferability**: Agent 协作 / 平台工程 / 合规
**Evidence Strength**: S4-S5
**Source**: ADR-0030 · FULL-CAPABILITY-REAUDIT · PHASE3.11-RUN-*/ · contracts/*
**Knowledge Status**: Runtime Validated

---

### K-043 · 文档准入四问（知识资产管理）

**Category**: METHODOLOGY
**Abstraction**: L3
**Value**: B
**Core Question**: 什么文档值得进 docs/？
**Problem**: 文档堆叠 → 可信度稀释 → 新贡献者无法判断"还成立吗"。
**Tafcm Evidence**: engineering-principles 文档准入四问：①现在还成立吗？②新贡献者需要吗？③能指导未来行为吗？④能脱离具体 session 理解吗？四问皆否 → archive/ 或删除；frontmatter 生命周期（active/deprecated/superseded/archived）。
**Decision**: 文档入口用准入四问过滤；生命周期显式化。
**Insight**: 知识库质量取决于准入与淘汰机制，而非写作量。
**Generalization**: 任何团队知识库都应设准入标准与生命周期标记。
**Transferability**: 团队 wiki / 个人知识库 / 文档体系
**Evidence Strength**: S5（长期执行）
**Source**: engineering-principles.md · agent-collaboration.md §7
**Knowledge Status**: Runtime Validated

---

### K-044 · 阶段化 + 门禁（Gate）驱动的演进纪律

**Category**: METHODOLOGY
**Abstraction**: L2
**Value**: B
**Core Question**: 如何防止架构演进失控？
**Problem**: 跨阶段实现、未立项大功能 → 范围失控。
**Tafcm Evidence**: Phase 0-3.11 全生命周期 + Phase 3.10 Final Gate G0-G12 全通过关闭；当前阶段空档期（不启动新大阶段功能、架构决策先落 ADR）。
**Insight**: 阶段门禁（Final Gate）让"阶段完成"成为可验证事件。
**Generalization**: 复杂项目用阶段门禁定义"完成"，防止持续开工。
**Transferability**: 项目治理
**Evidence Strength**: S5
**Source**: ROADMAP.md · AGENTS.md · GATE-REPORT.md
**Knowledge Status**: Runtime Validated

---

# Tafcm Knowledge Map

```
Tafcm
│
├── Product Knowledge
│   ├── ★ K-001 范式级批判驱动转向（WYSIWYG）     [L3·A·S5]
│   ├── K-002 五维定位命名框架                    [L2·B·S3]
│   └── K-003 功能自洽性检查                      [L2·B·S4]
│
├── Architecture Knowledge
│   ├── ★ K-004 六层分层 + CI 强制               [L3·A·S4]
│   ├── ★ K-005 .md 单一真相源                    [L3·A·S4]
│   ├── ★ K-007 Transaction + Live/Committed     [L3·A·S5] ↗ 可升维为 L4 原则
│   ├── ★ K-008 Renderer 不崩溃（降级）           [L3·A·S4]
│   ├── ★ K-009 可观测性内建                      [L3·A·S4]
│   ├── K-006 内容寻址资产                        [L3·B·S3]
│   ├── K-010 行为集中裁决                        [L2·B·S4]
│   └── K-011 Wrapping 非 Flattening              [L2·B·S4]
│
├── Engineering Patterns
│   ├── ★ K-012 Evidence Strength 分级 + 门禁     [L4·A·S4] ↔ 跨项目复用
│   ├── ★ K-013 能力契约机器真相源                [L3·A·S4] ↔
│   ├── K-014 Failure Identity 四层               [L3·B·S4]
│   ├── K-015 Golden 跨平台 + 镜像固定            [L2·B·S4]
│   ├── K-016 静态状态污染测试                    [L2·B·S3]
│   └── K-017 全量重算性能教训                    [L2·B·S5]
│
├── Agent Engineering（最独特知识域）
│   ├── ★ K-018 AI 权限矩阵 + Human Owner 边界    [L3·A·S5] ↔
│   ├── ★ K-019 Untrusted Analyzer 三段式         [L4·A·S4] ↔ ★★ 跨项目
│   ├── ★ K-020 ADI 诊断接口                      [L3·A·S4] ↔
│   ├── ★ K-021 置信度三态 + 错误成本不对称       [L3·A·S4] ↔
│   ├── ★ K-022 Agent Memory Distillation         [L3·A·S5] ↔
│   ├── ★ K-023 FFX Verification Orchestrator     [L4·A·S4] ↔
│   ├── ★ K-024 停止条件与升级路径                [L2·B·S5]
│   ├── ★ K-025 Agent 故障归因协议                [L3·A·S4]
│   └── K-026 AI Git 操作纪律                     [L2·B·S5]
│
├── Verification
│   ├── ★ K-027 E8 三层视觉保真（主观能力可测）   [L4·A·S5] ↔ ★★ 跨项目
│   ├── ★ K-028 Real vs Synthetic 验证循环        [L3·A·S5]
│   ├── K-029 消费端 ≠ 产品运行时                 [L3·B·S4]
│   ├── ★ K-030 ENV_MISSING ≠ 产品失败            [L3·A·S4] ↔
│   └── K-031 真机+截图+结构断言                  [L3·B·S5]
│
├── Design
│   ├── K-032 沉浸式 vs 卡片包裹                  [L2·B·S5]
│   ├── K-033 错误消息人话原则                    [L2·B·S4]
│   └── K-034 状态管理决策树                      [L2·B·S4]
│
├── Failure Lessons
│   ├── ★ K-035 多套存储隐性数据丢失              [L3·A·S5]
│   ├── K-036 Provider 重复定义幽灵 bug           [L2·B·S4]
│   ├── K-037 GBK 编码兜底                        [L2·B·S4]
│   ├── K-038 scoped storage 权限坑               [L1·C·S5]
│   ├── K-039 契约矛盾致 verify 误报              [L2·C·S3]
│   ├── K-040 静默吞异常 → 假空状态               [L2·B·S4]
│   └── K-041 时间预算乘积陷阱                    [L2·C·S5]
│
├── Decision Patterns        → 见 decision_patterns.md（9 个）
├── Failure Patterns         → 见 failure_patterns.md（9 个）
├── Evidence Chain           → 见 evidence_map.md（12 条）
├── Knowledge Candidates     → 见 knowledge_candidates.md（8 个）
│
└── Potential General Principles（L4 候选，见 candidates 与 K-007/K-012/K-019/K-027）
    ├── 复杂状态系统：持久状态、变更过程、历史记录不应共享职责边界（源自 K-007）
    ├── 验证体系必须显式定义证据强度链，禁止跨等级等价推断（源自 K-012）
    ├── AI 提供判断、系统掌握权力；不可信输入与执行权限分离（源自 K-019）
    └── "主观"能力的验证应先在结构层结构化（源自 K-027）

图例：★ 高价值  ↗ 可升维  ↔ 可跨项目复用  ? 需进一步验证
```

---
*Generated by Knowledge Archaeology · 只读 · 未修改任何仓库资产*
