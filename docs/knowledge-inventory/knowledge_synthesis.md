# Tafcm Knowledge Synthesis（Phase 2 · 知识提炼与升维）

> 输入：44 Knowledge Objects（K-001~044）+ 9 Decision Patterns（DP-01~09）+ 9 Failure Patterns（FP-01~09）+ 9 Candidates（C-001~09）+ 12 Evidence Chains
> 输出：Tafcm Knowledge Model —— 从"项目知识"收敛为"认知体系"的第二次升维。
> 性质：**不是** 44 篇文章的压缩；而是识别这些对象共同指向的更高层命题，并显式标注每个命题的认知状态。
> 状态声明：本模型为 **Tafcm-originated · Strongly evidenced · Cross-project validation pending**。
> 日期：2026-09-02 · 只读产物（未修改任何仓库资产）

---

## 0. 收敛方法：命题导向，而非归并导向

把 44 个对象压缩成 7 个原则，关键不是"把相似的堆在一起"，而是三步：

1. **确定研究命题**：Tafcm 让我们"认识到了什么"？→ 见 §6 元原则。
2. **问每个对象的证据指向**：它支撑的是"这个命题"，还是"通用优秀工程实践"，还是"项目档案"？
3. **三层分离**：把对象分到三个层面，**不强行全部装进核心模型**。

```
┌─────────────────────────────────────────────────────────┐
│ 核心命题层（Knowledge Model）—— 支撑"信任机制"命题        │  → 25 对象 → 7 原则
├─────────────────────────────────────────────────────────┤
│ 工程实践层（Engineering Practice）—— 独立可迁移工程经验    │  → 18 对象（有价值的实践，非命题证据）
├─────────────────────────────────────────────────────────┤
│ 项目档案层（Project Record）—— 项目特定事实               │  → 1 对象
└─────────────────────────────────────────────────────────┘
```

**这是收敛的核心纪律**：没有把所有 A 级对象都塞进原则。20 个 A 级中，一部分属于核心命题（如 K-019/K-027/K-012），一部分属于工程实践（如 K-004 六层、K-008 降级渲染——它们是优秀的普通工程原则，但不是"AI 信任机制"命题的证据）。

---

## 1. Q1：44 个 Knowledge Objects 实际上收敛成多少个核心知识？

**答案：44 → 25 个核心命题证据 + 18 个工程实践经验 + 1 个项目档案。**

| 层面 | 数量 | 对象 | 性质 |
|------|------|------|------|
| 核心命题层 | 25 | 见 §5 各原则挂接 | 支撑"AI 主导软件工程信任机制"命题 |
| 工程实践层 | 18 | K-004 K-008 K-010 K-011 K-015 K-016 K-017 K-032 K-033 K-034 K-036 K-037 K-038 K-039 K-040 K-041 K-043 K-044 | 优秀工程经验，独立成立，可迁移但非命题证据 |
| 项目档案层 | 1 | K-002（五维定位；2026-09-12 起用户侧收敛为三维 T/F/M，见 ADR-0033） | 项目特有事实 |

**判断说明**：
- K-004（六层分层+CI 强制）确实优秀，但它是"常规工程纪律"，40 年前的软件工程就懂——它不是 Tafcm 特有的认知增量，所以留在实践层。
- K-008（Renderer 降级）同理——"用户路径不崩溃"是好原则，但与"AI 信任"命题无直接关系。
- **真正进入核心层的 25 个，共同特征是：它们之所以存在，是因为"生产主体从人变成了 Agent"**。这是区分核心/实践层的判据。

---

## 2. Q2：9 个 Decision Patterns 可以进一步合并吗？

**答案：9 DP → 8 个映射进 7 原则；DP-09 降级为工程实践。**

| DP | 归入原则 | 理由 |
|----|---------|------|
| DP-01 Evidence Before Claim | **P1** | 直接定义"证据优先" |
| DP-02 Permission Boundary | **P2**（兼 P6） | 权限边界 = 权威分离 |
| DP-03 Single Source of Truth | **P3**（兼 P4） | 真相源唯一 = 状态/契约显式化 |
| DP-04 Contract First | **P4** | 契约先行 |
| DP-05 State Explicitization | **P3** | 状态显式化 |
| DP-06 Runtime/UI 解耦 | **P5** | 验证/渲染结构独立于执行 |
| DP-07 Deterministic + AI 分离 | **P2** | AI 判断、系统执行 |
| DP-08 环境/产品失败分类 | **P5**（兼 P1） | 错误分类决定归因 |
| **DP-09 预算整体建模** | **→ 工程实践层** | 性能/容量经验，非"AI 信任"证据 |

**关键发现**：DP-09 无法归入任何核心原则，这本身是有信息量的——它证明 7 原则的收敛不是"把所有模式硬塞进去"，而是有真实判别力。9 个 DP 中有 8 个是"信任/验证机制"维度，只有 1 个是纯工程维度。

---

## 3. Q3：9 个 Failure Patterns 揭示什么深层系统性问题？

**答案：失败不是随机的，7/9 指向同一个根源——"隐式性"（implicitness）。**

| FP | 直接原因 | 深层根源 |
|----|---------|---------|
| FP-01 语义偷换 | 证据等级未定义 | **隐式**证据语义 |
| FP-02 多源真相并存 | 无权威源 | **隐式**数据源 |
| FP-03 功能自相矛盾 | 能力未对齐 | **隐式**能力契约 |
| FP-05 静态状态污染 | static 共享 | **隐式**跨用例状态 |
| FP-06 静默吞异常 | 错误≈空 | **隐式**错误分类 |
| FP-08 契约漂移 | 缺元验证 | **隐式**契约引用 |
| FP-09 环境/产品混淆 | 分类粒度不足 | **隐式**失败维度 |
| FP-04 / FP-07 | 规模未建模 | 规模思维（独立维度） |

**元教训（Meta-Lesson）**：
> 在 Agent 主导的开发中，**隐式假设 = 未来事故**。人写代码时，"隐含约定"会被程序员靠直觉和上下文补全；Agent 不会——它只会按显式契约执行。因此 Agent 化工程对"显式化"的需求呈数量级上升。这 7 个失败模式不是 7 个独立 bug，而是**同一个结构性问题（隐式性）的 7 个投影**。

这正是 7 原则的共同动机：P1~P7 全部是"把某个隐式维度显式化"的不同侧面（证据、权限、状态、契约、验证、风险、失败）。

---

## 4. Q4：Tafcm 的全部知识能形成统一模型吗？

**答案：能——但不是 44 个知识点的树，而是一个以"元原则"为根、7 个原则为支干的统一模型。**

### 元原则（Meta-Principle）：Trust Engineering

> **当软件生产从"人写代码"转向"Agent 参与甚至主导代码生产"后，信任必须被工程化——从"人的判断"转换为"系统可验证的机制"。**

这 7 个原则不是并列的技巧，而是"信任"在不同维度的工程化：

| 维度 | 信任的什么 | 被工程化为 | 原则 |
|------|-----------|-----------|------|
| 判据 | 信任"声明" | 证据 | **P1 Evidence over Claim** |
| 主体 | 信任"AI 的权力" | 边界 | **P2 Authority over Intelligence** |
| 前提 | 信任"状态/记忆" | 显式化 | **P3 Explicit State over Implicit State** |
| 媒介 | 信任"约定" | 契约 | **P4 Contract over Convention** |
| 保证 | 信任"验证" | 结构独立 | **P5 Verification over Execution** |
| 尺度 | 信任"自动化" | 风险比例 | **P6 Risk-proportional Automation** |
| 演进 | 信任"修复" | 失败即证据 | **P7 Failure as Architectural Evidence** |

**这是"一个"模型**：7 个原则共享同一动机（Agent 不可信 → 显式化信任机制），通过同一元原则统一，并通过 §5 的挂接矩阵锚定到具体证据。

---

## 5. Tafcm Knowledge Model（统一模型 · 7 原则）

> 每原则：命题 → 挂接对象/模式/失败/候选 → 证据链 → Tafcm 案例 → 认知状态。
> 认知状态见 §7；主归属用 ●，交叉引用用 ○。

---

### P1 · Evidence over Claim（证据优先于声明）

**命题**：在 AI 协作工程中，任何"完成/修复/正确"的主张都必须由可复现证据支撑；可信度来自可审计的证明过程，而非宣称者身份或输出自信度。

- 挂接 Knowledge：K-012（证据强度分级）● K-013（能力契约）● K-028（Real vs Synthetic Loop）● K-029（消费端≠运行时）● K-030（ENV_MISSING≠FAIL）○ K-042（验证闭环）
- 挂接 Decision Patterns：DP-01 ●
- 挂接 Failure Patterns：FP-01 ● FP-09 ○
- 挂接 Candidates：C-002 ●
- 证据链：E-001 · E-002 · E-006
- **Tafcm 案例**：PDF 首个 Real Defect Repair Loop——`before=failed → after=passed → regression=passed` 的实证链取代"我修好了"声明（RUN-007）；Emulator PASS 被冻结为≠release gate PASS（RUN-013）。
- **认知状态**：Principle（Tafcm 强证据，跨项目待验证）

---

### P2 · Authority over Intelligence（权威高于智能）

**命题**：AI 的判断力不应自动伴随系统权限。AI 判断 ≠ 系统事实 ≠ 系统执行权限；不可信输入与执行权限必须处于不同信任域；AI 输出永远是"建议"，由确定性系统裁决。

- 挂接 Knowledge：K-018（权限矩阵）● K-019（Untrusted Analyzer）● K-020（ADI 诊断接口）○ K-021（置信度三态）● K-025（故障归因）● K-026（Git 纪律）●
- 挂接 Decision Patterns：DP-02 ● DP-07 ●
- 挂接 Failure Patterns：FP-09 ○
- 挂接 Candidates：C-004 ● C-008 ○
- 证据链：E-008 · E-012
- **Tafcm 案例**：issue-triage 三段式——`analyze job 零写权限`，Claude 的 --allowedTools 仅 Read/Glob/Grep/Write(限 findings.json)，即使被注入也无写令牌可借（ADR-0025）；AI_POLICY 权限矩阵按"可逆性+架构影响"分级。
- **认知状态**：Principle（Tafcm 强证据，跨项目待验证）——**已超出 Prompt Engineering，进入 Agent Governance / Control Architecture**

---

### P3 · Explicit State over Implicit State（显式状态优先于隐式状态）

**命题**：不同生命周期的状态（当前状态 / 变更事务 / 历史记录 / 记忆）必须显式建模并分离，不能被压进同一个状态容器；隐式状态在 Agent 协作下等于事故源。

- 挂接 Knowledge：K-007（Transaction + Live/Committed）● K-009（可观测性内建）● K-014（Failure Identity）● K-022（Memory Distillation）●
- 挂接 Decision Patterns：DP-03 ● DP-05 ●
- 挂接 Failure Patterns：FP-05 ●
- 挂接 Candidates：C-001 ● C-005 ●
- 证据链：E-003 · E-009 · E-012
- **Tafcm 案例**：Live/Committed 双态由 E2E 失败（LIVE-EDIT-01）逼出——"E2E 失败不是 bug，而是架构验证"；Agent Memory Distillation——无效删除、有价值归档、可复用提炼，运行时状态永不入库。
- **认知状态**：Principle（状态三面分离部分为 Tafcm 单一证据 → 标记 C-001 待跨项目）

---

### P4 · Contract over Convention（契约优先于约定）

**命题**：跨边界（Agent↔系统、工具↔系统、脚本↔脚本）的交互必须先定义机器可校验的契约；权威真相源唯一，一切派生必须通过同步/校验防漂移。

- 挂接 Knowledge：K-005（.md 单一真相源）● K-006（内容寻址）● K-013（能力契约）○ K-042（契约闭环）○
- 挂接 Decision Patterns：DP-03 ○ DP-04 ●
- 挂接 Failure Patterns：FP-02 ● FP-03 ● FP-08 ●
- 挂接 Candidates：C-007 ●
- 证据链：E-001 · E-004 · E-011
- **Tafcm 案例**：contracts/*.json 为机器真相源 + `ffx contract sync` 防漂移；context.md 输入契约强制 schema（schema 变更是契约变更，走 ADR）；FULL-CAPABILITY-REAUDIT 真实抓到 unknown_max 未同步的契约矛盾。
- **认知状态**：Principle（Tafcm 强证据）

---

### P5 · Verification over Execution（验证结构独立于执行）

**命题**：验证必须是独立于实现的结构层——编排器能力无关、验证只读不修、验证循环先于执行；且"验证能力本身要被验证"（元验证）。

- 挂接 Knowledge：K-020（ADI）○ K-023（FFX Orchestrator）● K-027（E8 三层视觉验证）● K-031（真机证据管线）●
- 挂接 Decision Patterns：DP-06 ● DP-08 ●
- 挂接 Failure Patterns：FP-08 ○
- 挂接 Candidates：C-003 ● C-006 ●
- 证据链：E-005 · E-006 · E-007
- **Tafcm 案例**：FFX 5 边界（Orchestrator 能力无关 / Adapter 注册表 / Runtime Bridge 直调生产类 / Artifact Producer / Consumer Adapter）+ 7 不变量（verify/diagnose 只读，repair-verify 只验证不修）；E8 把"视觉"拆为完整性→结构→像素三层，主观能力被结构化验证。
- **认知状态**：Principle（Tafcm 强证据，E8 像素层为探路）

---

### P6 · Risk-proportional Automation（风险比例的自动化）

**命题**：自动化程度与操作的"可逆性 × 影响"成反比；错误成本不对称决定自动化阈值；低风险自动执行、高风险留人类确认、中间态给建议。

- 挂接 Knowledge：K-018（权限矩阵）○ K-021（置信度三态）○ K-024（停止条件）● K-030（ENV_MISSING）○
- 挂接 Decision Patterns：DP-02 ○ DP-08 ○
- 挂接 Candidates：C-008 ● C-009 ○
- 证据链：E-008 · E-012
- **Tafcm 案例**：置信度三态——≥0.8 自动创建 Issue / [0.5,0.8) 仅建议 / <0.5 丢弃，"少建成本低、多建污染大"；Agent 停止条件——同一任务修复 >5 次未过 CI 必须停下请 Human；FFX 退出码 127（环境缺失≠产品失败）防止 Agent 误判后擅自行动。
- **认知状态**：Principle（阈值有效性 C-008 待真实数据校准）

---

### P7 · Failure as Architectural Evidence（失败即架构证据）

**命题**：批判与失败不是要掩盖的噪音，而是架构演进最高价值的证据输入；范式级缺陷需要范式级重构，而非打补丁。

- 挂接 Knowledge：K-001（范式级批判驱动转向）● K-003（功能自洽）● K-035（多存储数据丢失）●
- 挂接 Decision Patterns：DP-03 ○
- 挂接 Failure Patterns：FP-02 ● FP-03 ○ FP-06 ○
- 挂接 Candidates：C-009 ○
- 证据链：E-003 · E-004
- **Tafcm 案例**：CRITICAL-REVIEW（一份"每个判断带代码证据、按 P0-P3 分级"的批判报告）直接触发整轮 WYSIWYG 范式重构；三套存储事故 → 单一真相源决策。失败不是羞耻，是重构的路线图。
- **认知状态**：Principle（方法论在 Tafcm 反复验证）

---

### 挂接矩阵总览

| 原则 | 核心对象 | DP | FP | 候选 | 证据链 | 认知状态 |
|------|---------|----|----|------|--------|---------|
| P1 | K-012 K-013 K-028 K-029 K-030 K-042 | DP-01 | FP-01 FP-09 | C-002 | E-001/002/006 | Principle·pending |
| P2 | K-018 K-019 K-020 K-021 K-025 K-026 | DP-02 DP-07 | FP-09 | C-004 C-008 | E-008/012 | Principle·pending |
| P3 | K-007 K-009 K-014 K-022 | DP-03 DP-05 | FP-05 | C-001 C-005 | E-003/009/012 | Principle·pending |
| P4 | K-005 K-006 K-013 K-042 | DP-03 DP-04 | FP-02 FP-03 FP-08 | C-007 | E-001/004/011 | Principle·pending |
| P5 | K-020 K-023 K-027 K-031 | DP-06 DP-08 | FP-08 | C-003 C-006 | E-005/006/007 | Principle·pending |
| P6 | K-018 K-021 K-024 K-030 | DP-02 DP-08 | — | C-008 C-009 | E-008/012 | Principle·pending |
| P7 | K-001 K-003 K-035 | DP-03 | FP-02 FP-03 FP-06 | C-009 | E-003/004 | Principle·pending |

---

## 6. 收敛的完整链条（44 → 7 → 1）

```
44 Knowledge Objects
   │ 命题导向分层
   ├─ 25 核心命题证据 ──┐
   ├─ 18 工程实践经验 ──┤（有价值，独立留存，不进入模型）
   └─ 1  项目档案 ──────┘
                         ▼
             9 Decision Patterns → 8 进模型（DP-09 归工程层）
             9 Failure Patterns  → 7 进模型（FP-04/07 归工程层·规模维度）
             9 Candidates        → 9 全部挂接为"待验证"支撑
                         ▼
             7 Principles（P1~P7）
                         ▼
             1 Meta-Principle：Trust Engineering
```

---

## 7. Epistemic Status（认知状态体系）

知识库最稀缺的属性是**知道自己知道什么、不知道什么**。本模型为每个原则标注认知状态，沿这条链：

```
Fact → Observation → Hypothesis → Validated Pattern → Principle → Law
 │        │              │              │               │         │
项目事实  观察        候选(C)        跨ADR模式(DP)     Tafcm强证据  跨项目验证
                                                    (P1~P7)      (当前无，未来)
```

| 认知状态 | 含义 | 本模型中的实例 |
|---------|------|--------------|
| **Fact** | 项目事实，不泛化 | K-002 等档案层 |
| **Observation** | 单次观察 | 各失败案例 |
| **Hypothesis** | 有方向、证据不足 | C-001~C-009 |
| **Validated Pattern** | 跨 ADR/阶段重复出现 | DP-01~09 · FP-01~09 |
| **Principle** | 强证据 + 可迁移声明 | **P1~P7（当前层级）** |
| **Law** | 跨项目验证成立 | **暂无——需 FormulaFix/TeamMind/GrowthOS 验证** |

**状态声明（最高优先级）**：
> **P1~P7 目前都是 `Tafcm-originated · Strongly evidenced · Cross-project validation pending`。**
> 它们是有力的"当前最强解释"，**不是**最终定论。任何将其表述为普遍定律的行为，都违反本模型自身的第一原则（P1：证据优先于声明）。

---

## 8. 跨项目验证计划（如何把 P1~P7 从 Principle 推向 Law）

> 每条给出：验证什么 → 在哪个项目 → 需要什么证据 → 达标条件。

| 原则 | 验证项目 | 验证点 | 需要证据 | 达标条件 |
|------|---------|--------|---------|---------|
| P1 | FormulaFix 重构 / 任何 Agent 工程 | "声明必须有证据"是否仍成立 | 2+ 项目出现"无证据声明导致返工"或"证据门禁防住错误" | 跨项目出现 ≥2 次正向/反向证据 |
| P2 | TeamMind / GrowthOS | 三段式信任边界在非 GitHub 副作用下是否适用 | 客服工单/配置修改/内容审核场景复用 | 1 个项目完整落地 + 注入攻击成功率下降 |
| P3 | FormulaFix 编辑器 / 其他富编辑器 | 状态三面分离是否降低耦合 | 重构前后缺陷率/耦合度对比 | 第二项目独立验证 |
| P4 | GrowthOS / 数据迁移 | 契约机器化 + 元验证 | 契约漂移误报案例的减少 | 契约系统在第二项目落地 |
| P5 | TeamMind / 任何 Agent 可编程系统 | 验证编排器独立于执行 | 能力扩展时 orchestrator 零改动 | 接入第 3 个能力仍零改动核心 |
| P6 | 个人 Agent 自动化 | 错误成本不对称阈值 | precision/recall 真实数据 | 三态阈值经真实数据校准有效 |
| P7 | FormulaFix 重构 | 范式级批判方法论 | 第二份"范式级批判报告"驱动重构 | 方法论跨项目复用成功 |

**注意**：P7 与 K-001 是元方法论——"批判驱动重构"本身可迁移，但每次应用都要重写批判，不能复制结论。

---

## 9. 与飞书两层结构的映射（最终知识库形态）

```
Tafcm 项目知识库（飞书空间）
│
├── 01 Project Layer（项目层 · 事实与档案）
│   ├── 产品（定位/能力/UX）
│   ├── 架构（六层/模块/ADR）
│   ├── 验证（contracts/evidence/regression）
│   ├── 开发（工具链/CI/调试）
│   └── 历史（Phase/roadmap/audit）
│
└── 02 Knowledge Layer（知识层 · 认知模型）← 本次 Synthesis 的落点
    ├── Evidence（P1）
    ├── Authority（P2）
    ├── State（P3）
    ├── Contract（P4）
    ├── Verification（P5）
    ├── Automation Risk（P6）
    ├── Evolution（P7）
    └── 03 Candidates（C-001~09 · 明确标注 Hypothesis 状态）
```

**两层分离的承诺**：飞书与 GitHub 各司其职——GitHub 存事实与可执行资产；飞书的 Knowledge Layer 存"提炼后的认知模型"，**两者不重复**。Candidates 明确标注为"待验证假说"，绝不以"真理"姿态写入。

---

## 10. 结论：Tafcm 最终贡献给知识体系的，是什么

> Tafcm 最有价值的发现，不是"这是一个规范的 Flutter 项目"，而是一个清晰的研究命题：
>
> **当软件生产从"人写代码"转向"Agent 参与甚至主导代码生产"后，传统的软件工程保障机制需要如何重构？**
>
> 本模型给出的候选答案（等待跨项目验证）：把"信任"从人的判断，工程化为七种系统可验证的机制——用证据替代声明（P1）、用边界约束权力（P2）、用显式化消灭隐式事故（P3）、用契约替代约定（P4）、用独立验证保证执行（P5）、用风险比例决定自动化（P6）、用失败作为架构进化的证据（P7）。
>
> Tafcm 是这个问题的一个小型实验场，**且是目前唯一完整跑完整个实验的记录**。它的认知价值在"实验记录"本身——这是把它升维进个人知识体系时，最不可替代的部分。

---

*Generated by Knowledge Archaeology · Phase 2 Synthesis · 只读 · 未修改任何仓库资产*
