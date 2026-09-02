# ADR-0032: Cline 增量审查模型 —— Audit Frontier

- **状态**：Draft（Doubao Supervisor 起草，SUP-03，待 Human Owner 审批合入）
- **生效日期**：待定
- **决策者**：Human Owner（审批）+ Doubao Supervisor（起草）
- **关联**：SUP-04 · POLICY.md §2.3.2 · PROMPT.md §1/§11 · FRONTIER.md · validate_audit.py
- **Supersedes**：PROMPT.md §11 旧版"每日全盘重扫"执行流程；不改变 POLICY §2.1-2.3 权限矩阵边界

## 背景

2026-09-01 至 09-03 双 Agent 治理落地后，Doubao Supervisor 对 Cline Maintainer 的审查质量做独立核验，确认其**广度铺开、深度不足**：Cline 每日全盘扫描 12 类对象 + 11 类文档，但未发现 #238（kAppVersion 版本漂移）、#239（Mermaid 不随主题切换）、#240（外部文件无法保存）这类真实产品缺陷，9-03 甚至宣称 "No significant findings"。

根因不是 Cline"不认真"，而是**审查模型本身**：
1. 每日全盘重扫 → 每个区域只看一点，深度永远归零；
2. 代码三个月未改的区域永远不再被深入；
3. 无"未闭合证据链"的持久化 → 每天从零开始，无法积累审查深度；
4. Cline 无运行能力（无真机/无 flutter run），但 PROMPT 未明确其能力边界 → 对需运行验证的问题臆断或漏报。

## 决策

### 1. 增量审查模型（Incremental Audit）

Cline 不再"每日全盘重扫"，改为**持续建立并推进 Audit Frontier**（审查前沿）。审查优先级：
**Frontier 未闭合项 > 新增代码/Issue 触发 > 其余风险扫描**。

**增量三触发器**（防止"增量 = 只看 git diff"）：
- **Change-driven**：代码 / 依赖 / PR / 测试失败变化 → 重审变化路径
- **Risk-driven**：高风险但长期未修改的区域 → 逐轮深入（代码三个月没动也要审）
- **Evidence-driven**：上轮未闭合证据链 → 本轮优先续追

### 2. Audit Frontier（未闭合审查任务队列）

- 持久化于 `.agent/tafcm-maintainer/FRONTIER.md`，Entry 含：`id / area / depth(current,target) / open_question / next_action / blocking_reason / last_verified_at / activation_reason / verification_status / handoff`
- **depth target 由 Cline 提议，周度 Supervisor Pass（SUP-01）校准**，不允许 Cline 自定 target 提前"闭合"
- **闭合必须有产出物**：Issue 链接或 confirmed/rejected 证据落点
- **生命周期**：candidate → active → deepening → blocked → verified → cooling → retired
  - cooling：连续 3 轮无代码变化 / 无新证据 / 无新异常 → 释放审查预算
  - reactivation：新代码命中 / 新 Issue / 测试失败 / 新 Evidence → cooling → active
  - retired：归档（保留 retired_at + retire_reason），可重激活——归档不是删除

### 3. 验证能力分层（Capability Ladder）

Cline 的验证能力按"证据获取深度"分层建模，**不假设能突破 Runtime 边界**：

| Level | 能力 | 沙箱可实现 | 白名单现状 |
|-------|------|-----------|-----------|
| L1 | 静态分析（git / grep / AST / 文档） | ✅ | 已具备 |
| L2 | 定向测试 `flutter test <target>` | ✅ | 已具备（`flutter test *`） |
| L3 | 诊断脚本（contract check / regression check / migration check） | ✅ | 已具备（python/pytest） |
| L4 | 可自动化的 headless integration test | ⚠️ 部分 | 视 job 而定 |
| L5 | 设备依赖（真机 / GUI / 摄像头 / 性能） | ❌ GitHub runner 无设备 | 不可跨过 |

L5 是**显式不可跨越的边界**。Cline 达到边界时写正式状态 `verification_status: needs-device-validation` + `handoff`（executor + reason），按 SUP-03 交 Supervisor / 人工；Evidence 回流后从 Frontier 恢复，不臆断代替验证。

### 4. 辅助观察项降级

Issue 状态 / CI 状态 / 文档格式 / README / Roadmap / CHANGELOG 从"每日全盘审查"降为**辅助观察项**（低频快照，只报变化），把 Context / Token 预算释放给 Frontier 深挖（代码 / 调用链 / 测试 / 证据 / Runtime 疑点）。

## 后果

### 正面
- 审查深度随轮次单调递增（"这一次永远比上一次更深"）
- 风险成为动态资源（cooling/reactivation），不是永久重点
- Cline 能力边界被显式建模：`needs-device-validation` 成为机器可读状态，与 SUP-03 handoff 闭环
- 项目积累"技术记忆"：retired Entry 保留深度轨迹，未来可重激活

### 代价 / 风险
- Frontier 维护成本：Cline 每日需更新 FRONTIER.md（新增 1 步流程）；validate_audit.py 增加校验
- 初始建立 Frontier 需要 1-2 轮：第一批 Entry 由 Cline 从现有高风险区域（导出链路 / 公式渲染 / 编辑器事务 / WebView / autosave）初始化
- 与 #238/#239/#240 的衔接：这些已确认问题应作为首批 Frontier Entry 或 closed Issue 处理，不重复审查

## 验证

- 合入后首个完整 cycle：Cline 从 FRONTIER.md 选择 Entry → depth N→N+1 → Audit 含 Frontier 推进记录 → validate_audit.py 通过（frontier 字段校验）
- 周度 Supervisor Pass 校准 depth target，并抽查 Cline 是否"真的比昨天深"（对比 FRONTIER.md 推进记录）
- 回归：现有 Audit 五块校验不破坏；FRONTIER.md 不存在时 validate 向后兼容（不 fail）
