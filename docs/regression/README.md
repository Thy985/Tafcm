# Regression Assets（回归资产）

**定位（L4 机器资产）**：从历史 RUN 报告提取的**可执行/可核对**回归案例包。
每个 BUG 一个目录：`case.json`（元数据）+ `input.md`（最小输入）+ `expected.json`（不变量）+ `README.md`（背景）。

**原则**：README 只解释背景；`case.json` / `expected.json` 才是可核对资产。
与 `tests/verification_cases/`（运行时 corpus）互补：本目录是人类可读的 case 包，tests/ 是可执行语料。

## 索引

| ID | 能力 | 标题 | 来源 | 状态 |
|----|------|------|------|------|
| [BUG-001](markdown/BUG-001-hard-break/) | markdown | 多行段落合并丢失硬换行 | ADL-LOOP-RUN-008 | ✅ fixed |
| [BUG-002](markdown/BUG-002-pipe-line/) | markdown | `\|` 开头非表格行被静默吞掉 | ADL-LOOP-RUN-008 | ✅ fixed |
| [BUG-003](markdown/BUG-003-list-order/) | markdown | 列表项后紧跟段落顺序错乱 | ADL-LOOP-RUN-008 | ✅ fixed |

## 提取来源

- ADL-LOOP-RUN-008：BUG-1/2/3（fuzz 首轮发现，markdown_parser +17/-3）
- 待提取候选：BUG-4（CRLF 任务列表）/ BUG-5（嵌套列表）/ BUG-6（空 mermaid 块）
  —— 见 `archive/runs/adl/ADL-LOOP-RUN-008.md`；本轮提取前 3 个作范式，
  其余按需补充（不重复造轮子，历史报告始终是完整真相）。
