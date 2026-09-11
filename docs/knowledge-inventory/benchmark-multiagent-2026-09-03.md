# Multi-Agent Benchmark · Tafcm 反例压力测试（2026-09-03）

> 实验目的：验证升级后的 Multi-Agent Knowledge Archaeology System（counterexample-hunter + reconciler）是否比单 Agent 版产出更准的知识。
> 实验对象：Tafcm 已有原则 P2（Intelligence ≠ Authority：AI 不直接拥有执行权 / 一切经受控工具）。
> 实验方法：workflows/benchmark.md 的反例压力测试——对 P2 主动搜索 bypass / admin path / direct call / test path / 例外路径。

---

## 一、实验对象：P2 的原始 claim

> **P2 · Intelligence ≠ Authority**：AI 判断（智能）与执行权（权威）分离；Agent 影响状态的动作必须受控接口化；AI 不直接读/改/执行。

**旧版状态**：`Tafcm-originated · Strongly evidenced · Cross-project validation pending`

## 二、Counterexample Hunter 发现的反例（带 source）

| # | 反例 | source | 类型 |
|---|------|--------|------|
| CE-1 | AGENTS.md §6.4：Human Owner 明确授权时，AI 可以 commit 架构决策类文件（绕过默认禁令） | AGENTS.md:303 | 例外授权路径 |
| CE-2 | AGENTS.md §12.2：**曾存在**"绕开 git 安全护栏直接改写底层存储"的 bypass 流程（commit-tree/update-ref/printf > .git/refs/... 红线操作）——后因自身造成两次仓库损坏被 RETIRED | AGENTS.md:623-633 | 曾存在的高风险 bypass（已退役） |
| CE-3 | E8 视觉验证后端可被环境变量覆盖：`FFX_E8_VISION_BACKEND=none|force`、`FFX_E8_VLM_BACKEND=none`（VLM 禁用 → 直接 OCR 链） | harness/e8_vision.py:203、e8_vlm.py:67 | 验证链配置开关（降级） |
| CE-4 | `CLI_ANYTHING_FORCE_INSTALLED=1` 强制要求已安装命令 | utils/helpers.py:15 | 环境强制开关 |
| CE-5 | ffx `project` 组含 `set-field / save / undo / redo / snapshot / export`——AI 可经 ffx 直接修改 ffx 自身项目状态 | ffx_cli.py | AI 可直接执行的写操作（但作用于 ffx 状态，非 Tafcm 源码） |

## 三、Reconciler 的冲突处理

三个"看起来冲突"的观察其实在不同层面：

```
claim: AI 不直接拥有执行权
  design_intent: true            （doc-analyst：AGENTS.md 权限矩阵）
  implementation: 大部分 true    （code-analyst：ffx/adi 受控接口）
  tested_behavior: true          （test-analyst：架构守门测试）
  exception_paths: 存在           （counterexample-hunter：CE-1~CE-5）
status: CONDITIONAL
```

关键裁决：
- **CE-1 不是 P2 反例，而是 P2 的印证**：例外授权属于 **Human Owner**，不是 AI——"执行权转移"仍发生在人类权威之下，授权链没有断裂，只是从"AI 不可"变成"人类可授权 AI"。
- **CE-2 是真实反例但已被时间证伪**：bypass 路径曾存在，**它本是为了应对仓库损坏，结果自己成了损坏的主要来源**——这给 P2 增加了一个深度维度：bypass 不是免费的，它本身就是风险源。
- **CE-3 是设计好的降级链**，不是安全绕过——验证后端降级是功能特性（VLM 不可用 → OCR 链），不违反"验证独立于执行"。
- **CE-5 是范围问题**：ffx 项目状态 ≠ Tafcm 源码。AI 可写 ffx 自身状态，不能写产品源码——P2 的"执行权"边界需要按对象分层。

## 四、条件化后的 P2（实验产出）

> **P2-C · Intelligence ≠ Authority（条件化版）**
>
> 默认路径：AI 判断与执行权分离，Agent 影响产品源码的动作必须经受控接口（ffx/adi），验证独立于执行。
>
> **适用条件（applies_when）**：
> 1. 授权转移只发生在人类权威之下（Human Owner 可授权 AI 执行默认禁止的操作）——例外授权仍在权威链内
> 2. 验证链的降级开关（env override）是设计特性，不破坏"验证独立于执行"
>
> **不适用（does_not_apply_when）**：
> 1. 存在 bypass 基础设施时（如曾经的 git 底层绕过）——bypass 路径本身成为风险源，必须显式退役
> 2. AI 可写"非产品源码"的对象（工具自身状态）——执行权边界需按对象分层定义

**认知增量**：旧版 P2 是一句强断言；新版 P2-C 是一组带边界条件的工程准则。**"条件化"不是弱化原则，而是让原则可执行、可检验。**

## 五、Benchmark 指标

| 维度 | 单 Agent 版（旧） | Multi-Agent 版（新） |
|------|------------------|---------------------|
| 反例发现 | 无机制 | 5 个反例（CE-1~CE-5），其中 CE-2 是深度发现 |
| 条件化知识 | 无（P2 是强断言） | P2-C（带 applies_when / does_not_apply_when） |
| 过度升维阻止 | 无机制 | CE-2 证明 bypass 有代价 → 阻止"无条件信任授权链" |
| 冲突价值 | 无（单 Agent 自我确认） | CE-1 被裁决为"印证而非反例"（层面分离） |
| 证据支撑 | P2 有证据但无反例核验 | P2-C 带完整反例清单（CE-1~5 + source） |

## 六、结论

**Multi-Agent 架构达到升级目标**：Counterexample Hunter 发现了单 Agent 版完全不可能发现的维度（CE-2 的"bypass 自噬"教训），Reconciler 把 P2 从强断言升级为带边界的可执行准则 P2-C。这正是"交叉验证 + 冲突裁决 + 质量闭环"的价值——旧版是"一个有信心的作者"，新版是"一个接受同行评审的作者"。

> **对 skill 自身的验证**：反例压力测试是 Multi-Agent 版最有价值的独有能力。建议作为 benchmark 的必跑项。
