---
status: active
type: principle
owner: maintainers
last_reviewed: 2026-08-30
---

# Engineering Principles（工程总原则）

> 本文件是 Tafcm 工程实践的**稳定总原则**——回答"我们为什么这样做"。
> 高度稳定，不随具体 Agent Coding Session 或临时决策变化；修改需 Human Owner 批准。
> 提炼源：AGENTS.md §1 / §6（禁止事项）、.agent/AI_POLICY.md §4、REPO_POLICY.md。

## 总原则

1. **Correctness before convenience**
   正确性优先于开发便利。任何"先能用、后正确"的捷径必须显式记录为已知债务（DEBT 表），不得静默引入。

2. **Runtime behavior is the source of truth**
   运行时行为是唯一真相。文档、注释、测试与真实运行不一致时，以真实运行（含真机、CI、E2E）为准，并修正文档。

3. **Visual output must be testable**
   视觉输出必须可测试。渲染结果应有可重复的验证手段（golden 基线 / 结构断言 / E2E 截图），不允许"肉眼验收"作为唯一证据。

4. **Every critical behavior requires reproducible evidence**
   每个关键行为必须有可复现证据。证据强度分级（synthetic < test < production < virtual < physical < visual < human_confirmed），发布门禁以高等级证据为准。

5. **Prefer small, composable transformations**
   优先小而可组合的变换。单一职责（一个 `.dart` 文件 = 一个类/主题/Provider 簇，超 400 行必须拆分）；能改一行不改两行。

6. **Avoid undocumented magic behavior**
   禁止未记录的魔法行为。服务类构造函数注入（不写全局静态方法）；核心逻辑必须有 dartdoc 或 ADR 依据；禁止 `print()`（用 `debugPrint()`）。

7. **Changes must preserve backward compatibility unless explicitly versioned**
   变更必须保持向后兼容，除非显式版本化。公共 API（导出接口、Provider 签名、数据模型）变更需请求批准并记录。

## 分层依赖（架构底线）

- 六层自上而下依赖：`core → data → domain → providers → presentation`，循环依赖零容忍。
- `core` 禁止反向 import `presentation` / `domain`；`data` 只允许 import `core` 之外的业务代码边界。
- 架构守门由 CI 测试强制（layer_dependency / file_access / provider_uniqueness / file_size），不以评审口头约定代替。

## 最小改动与范围纪律

- 不顺手重构无关代码；不引入未被请求的依赖/功能。
- 重构 PR 必须 0 业务行为变化；大规模重构与功能改动不得混在同一 PR。
- 修改前必读 AGENTS.md 相关章节，改动范围与 PR 描述一致，不夹带未说明的改动。

## 工程禁区（不得触碰的底线）

- 禁止删除测试以通过 CI（失败必须修代码）。
- 禁止在 UI 层直接展示异常 detail / stack。
- 禁止在 `main()` 中写业务逻辑。
- 禁止引入新的全局静态状态。
- 禁止把架构决策类文件（AGENTS.md、ADR）当普通文档随意修改——改动需 Human Owner 授权。

## 文档准入（知识资产四问）

任何文档进入 `docs/` 前必须通过：

1. 现在还成立吗？
2. 新贡献者需要它吗？
3. 它能指导未来的工程行为吗？
4. 它能脱离具体 Agent Session 单独理解吗？

四问皆否 → 不进入 `docs/`（进 `archive/` 或删除）。
