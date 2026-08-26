# INVESTIGATIONS — 跨会话调查入口 / Investigation Index

> **位置**: `docs/INVESTIGATIONS.md`（2026-08-25 由根目录迁移至此，PR-2 `chore/root-cleanup-2026-08-25`）
> **定位**: 跨会话、长期可复用的调查索引；不是一次性 scratchpad。
> **层级**:
> - `docs/` — 人类长期知识 / 项目文档
> - `.agent/` — Agent governance
> - `.agent/state/` — Agent 运行时状态（不入库）
>
> 临时运行状态不入此文件，存于 `.agent/state/<run-id>/`。
>
> ---

# INVESTIGATIONS — 跨会话调试上下文记录

> 本文件记录正在进行的调试/调查任务，让每个新会话能无缝接上上一个会话的进度。
> 每条记录格式：`[ISO时间] <标题> | 状态 | 下一步`

## 格式

```markdown
### <任务简称> —— <一句话描述>
- **开始**: <ISO时间>
- **状态**: investigating | blocked | waiting_for_user | resolved
- **关联**: <issue/PR/跑号>
- **根因**: <若有>
- **证据**: <关键 log/stack/test path>
- **下一步**: <具体动作>
```

---

## 活跃调查

> 在此添加当前正在进行的调查。完成后移至 §已完成。

（暂无活跃调查）

---

## 已完成

> 归档已解决的调查，方便回溯。

（暂无）

---

## 临时 notes

> 零散的观察、待确认项、想到但未展开的思路。

- 2026-08-17: Claude Code 洞察报告生成，触发本次 AGENTS.md §12-15 追加任务。
