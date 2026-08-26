# FormulaFix 信息架构重构设计（Phase 3.12）

**日期**: 2026-08-27
**状态**: Proposed（设计先行，未执行迁移）
**范围**: 四层信息架构（人类入口 / 工程真相 / 历史档案 / 机器资产）+ 目标目录结构
**原则**: 当前知识 ≠ 历史知识；人类知识 ≠ 机器资产；决策 ≠ 实现；证据 ≠ 结论

---

## 1. 分层原则（四层）

| 层 | 目录 | 回答的问题 | 消费者 |
|----|------|-----------|--------|
| **L1 人类入口** | `README.md` + `docs/README.md` | 项目是什么？怎么快速上手？ | 人类新人 |
| **L2 工程真相** | `docs/product/` `docs/architecture/` `docs/engineering/` `docs/decisions/` | 现在系统是什么？为什么这么设计？完成度如何？ | 人类 + Agent |
| **L3 历史档案** | `docs/archive/` | 过去发生了什么？怎么演进的？ | 追溯者（人类 + Agent） |
| **L4 机器资产** | `contracts/` `tests/verification_cases/` `flutter_app/test/golden/` `.adi/` | 可机器消费的验证/证据/契约 | FFX / ADI / CI |

---

## 2. 目标目录结构（迁移后）

```
math2/
├── README.md                         # L1 人类首页：5 分钟理解项目（100-200 行）
├── AGENTS.md                         # L1 Agent 入口：如何协作（保留，微调）
├── .agent/
│   ├── REPO_POLICY.md                # 安全层总纲（保留）
│   ├── ENVIRONMENT.md                # 仓库物理边界（保留）
│   ├── GIT_RULES.md / GIT_POLICY.md  # git 治理（保留）
│   ├── AI_POLICY.md / COMMAND_SAFETY.md（保留）
│   ├── CURRENT-STATE.md              # ★ 新增：Agent 当前状态入口（Current State Truth）
│   ├── context/ templates/ tools/ state/（保留）
│
├── contracts/                        # L4 机器资产（★ 保留原位——ffx contract_sync 依赖 root/contracts/*.json）
│   ├── markdown_parser.json
│   ├── serializer.json
│   ├── formula.json
│   └── ...（11 个，不动）
│
├── design-system/                    # L4 设计 tokens（保留）
│
├── docs/
│   ├── README.md                     # L1 文档门户：按阅读目的导航（重写）
│   ├── INDEX.md                      # 全量索引（保留 + 更新）
│   │
│   ├── product/                      # L2 产品真相
│   │   ├── PRODUCT.md                # 产品是什么（← README 产品段 + DESIGN.md 收敛）
│   │   ├── CAPABILITY-STATUS.md      # 当前能力完成度（← FEATURE-* 矩阵收敛 + PHASE3.10 基线状态）
│   │   └── UX-GUIDE.md               # 产品体验/设计原则（← UI_SPEC.md 收敛）
│   │
│   ├── architecture/                 # L2 架构真相
│   │   ├── ARCHITECTURE.md           # 当前架构总览（瘦身：只讲现在，不讲为什么）
│   │   ├── EDITOR-MODEL.md           # 编辑模型（← ARCHITECTURE 编辑段 + ADR-0008/0012 实现态）
│   │   ├── EXPORT-MODEL.md           # 导出架构（← ARCHITECTURE 导出段）
│   │   ├── UI-COMPONENT-MODEL.md     # UI 组件模型（← Component-Tree.md 收敛）
│   │   └── AGENT-ENGINEERING.md      # ADI/FFX/验证闭环（← FFX-VERIFICATION-ORCHESTRATOR-v1.md 收敛）
│   │
│   ├── engineering/                  # L2 工程真相
│   │   ├── ENGINEERING-BASELINE.md   # 工程基线 + DEBT 表（← PHASE3.10-ENGINEERING-BASELINE-v1.md 重命名收敛）
│   │   ├── VERIFICATION-POLICY.md    # 验证纪律（← E2E_TEST_PLAN + TEST_GAP_PLAN + TEST_SKIP_REGISTRY 合并）
│   │   ├── DEVELOPMENT-RULES.md      # 开发规则（← CODING_RULES.md）
│   │   ├── GIT-WORKFLOW.md           # Git 流程（← GIT_WORKFLOW.md）
│   │   └── WORKFLOW.md               # 开发流程（← WORKFLOW.md）
│   │
│   ├── decisions/                    # L2 决策真相（Decision Truth）
│   │   ├── INDEX.md                  # ADR 索引（状态表：有效/需复审/已废弃——★ 从 README 拆出）
│   │   └── ADR/                      # ★ docs/ADR/ 移入（29 篇，不动内容）
│   │
│   ├── contracts/                    # L4 人类版任务契约（← docs/contracts/ 保留，16 篇）
│   │   └── phase*.md
│   │
│   ├── regression/                   # L4 回归资产（★ 从 RUN 报告提取，机器可执行）
│   │   ├── markdown/                 # ← ADL-RUN BUG-1/2/3 等
│   │   ├── serializer/
│   │   ├── formula/
│   │   └── README.md                 # 只解释背景，case 本身是资产
│   │
│   ├── evidence/                     # L4 证据资产（★ 从 RUN 报告提取，可追溯）
│   │   ├── capability/               # 能力证据（← E6/E8 截图 + 判定）
│   │   ├── visual/                   # 视觉证据（← vlm_corpus 等）
│   │   └── consumer/                 # 消费端证据（← Word/PDF 验证）
│   │
│   └── archive/                      # L3 历史档案（★ 从 docs/ 顶层收敛）
│       ├── runs/                     # ← docs/runs/ 移入（35 篇 RUN 报告）
│       ├── audits/                   # ← AUDIT / REVIEW / 审计类（CRITICAL_REVIEW 等）
│       ├── spikes/                   # ← SPIKE / 调研类（MIGRATION-SPIKE 等）
│       ├── investigations/           # ← INVESTIGATIONS 等
│       └── old-designs/              # ← DESIGN.md / UI_SPEC.md 旧版 / REFACTOR_DESIGN.md
│
├── flutter_app/                      # 主项目（保留）
│   ├── lib/ test/ integration_test/ tool/ docs/
│   └── test/golden/                  # L4 视觉基线（保留）
│
├── tests/verification_cases/         # L4 回归案例（保留，已有 corpus）
├── tools/                            # ffx-cli / adi（保留）
└── skills/ formulafix-redesign.design/（保留）
```

---

## 3. 与现状的关键差异（迁移决策）

| # | 现状 | 目标 | 决策理由 |
|---|------|------|---------|
| D1 | 根 `contracts/*.json`（11 个） | **保留原位** | ffx `contract_sync.py` / `contract.py` 硬编码 `root/contracts/*.json`，移动会破坏机器资产路径 |
| D2 | `docs/ADR/`（29 篇） | 移入 `docs/decisions/ADR/` | ADR 是 Decision Truth，与索引同层；纯 git mv，内容不动 |
| D3 | `docs/runs/`（35 篇 RUN） | 移入 `docs/archive/runs/` | RUN 是历史证据（L3），不污染 Current State |
| D4 | `docs/` 顶层 40+ 篇 | 分流到 product/architecture/engineering/archive | 顶层只留 README/INDEX 门户 |
| D5 | `FEATURE-*` 矩阵 ×2 | 收敛为 `product/CAPABILITY-STATUS.md` | 人类视图收敛，机器视图在 contracts/ |
| D6 | `RUN-008 BUG-1` 等 | 提取为 `regression/markdown/BUG-001/`（case.json + input.md + expected.json） | 报告 → 可执行资产 |
| D7 | `E2E_TEST_PLAN` + `TEST_GAP_PLAN` + `TEST_SKIP_REGISTRY` | 合并为 `engineering/VERIFICATION-POLICY.md` | 验证纪律单一真相 |
| D8 | 顶层重复的 `PHASE3.11-RUN-*.md`（16 个，与 runs/ 下重复） | **删除顶层副本，保留 runs/ 下** | main 上 PR #164 顶层副本 + PR #166 runs 副本并存，内容相同——需清理 |
| D9 | `AGENTS.md` | 保留 + 微调（指向 CURRENT-STATE） | Agent 入口只负责协作/边界/纪律 |

---

## 4. 三种真相（Three Truths）

| Truth | 载体 | 回答 | 更新者 |
|-------|------|------|--------|
| **Decision Truth** | `docs/decisions/ADR/` + `INDEX.md` | 为什么这么做？ | Owner 审批 |
| **Evidence Truth** | `contracts/` `regression/` `evidence/` `golden/` `.adi/` | 实际发生了什么？ | FFX / ADI / CI（机器写入） |
| **Current State Truth** | `.agent/CURRENT-STATE.md` + `product/CAPABILITY-STATUS.md` + `engineering/ENGINEERING-BASELINE.md` | 现在到底是什么状态？ | Agent + Owner 维护 |

而 RUN / AUDIT / SPIKE / INVESTIGATION 一律视为**历史证据/推理过程**（L3），可追溯但不作 Current State。

---

## 5. 双入口

```
人类：README → docs/README → product/architecture/capability/engineering
Agent：AGENTS → .agent/CURRENT-STATE → contracts → policies → ffx/adi
        ↓
      共享底层资产（contracts/ regression/ evidence/）
```

---

## 6. 迁移顺序（十步，不一次性大搬迁）

1. 建立新目录 + canonical 文档骨架（product/ architecture/ engineering/ decisions/）
2. 建立 `docs/MIGRATION-MAP.md`（本设计配套的完整迁移表）
3. 提取 contracts / regression / golden / evidence（报告 → 资产）
4. 整理 ADR（移入 decisions/ + 重建 INDEX）
5. 整理 Architecture / Product / Engineering（瘦身 + 拆分）
6. Run / Audit / Spike 移入 archive
7. 重写 README / docs README（人类入口）
8. 全文引用检查 + dead link 检查
9. FFX / Agent 定位 canonical sources（更新 tools/ffx-cli 引用若需）
10. Human Review

---

## 7. 验收标准（DOCUMENT CONSOLIDATION PASS）

**Human**：
- [ ] 新人只看 README + docs/README 能理解项目
- [ ] 能从 architecture/ 理解当前系统
- [ ] 能从 product/CAPABILITY-STATUS 知道完成度
- [ ] 能从 decisions/INDEX 理解关键历史决策

**Agent**：
- [ ] 不读 RUN/AUDIT 即可获得当前状态（CURRENT-STATE + contracts）
- [ ] contracts 机器可读（保留 root/contracts/）
- [ ] regression 可直接执行（case.json 资产化）
- [ ] evidence 可追溯（回归到原始 RUN）

**Governance**：
- [ ] 一个事实只有一个 canonical source
- [ ] ADR 状态与代码一致
- [ ] 历史文档全部可追溯但不污染 Current State
- [ ] 无大量重复定义（含顶层 RUN 重复副本清理）
- [ ] 死链接清零
