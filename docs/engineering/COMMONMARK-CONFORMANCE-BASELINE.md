# CommonMark 一致性基线（U1 Spec Conformance Baseline）

> **U1 交付物**（[TEST-SYSTEM-UPGRADE-PLAN.md](TEST-SYSTEM-UPGRADE-PLAN.md) §3.1，学 Markwon/commonmark-java 的"规格即测试数据"范式）
> **spec 版本**：0.31.2（652 例 / 25 sections）｜**数据**：`flutter_app/test/parser/spec/`
> **生成日期**：2026-09-11｜**基线 commit**：Wave 3

## 1. 总量

| 指标 | 数值 |
|------|------|
| spec 用例总数 | 652 |
| 当前通过 | **358（54.9%）** |
| 崩溃（parser 抛异常） | **0**（守门测试零容忍项） |

> §9 曾估计兼容率"约 60-70%"——精确数字为 **54.9%**。差异来源：spec 用例含大量边角输入（实体引用、多级嵌套、链接引用定义），比日常写作语法更严苛。两套口径互补：spec 测"符合标准"，round-trip fuzz 测"自洽保真"。

## 2. 分节通过率（首次基线快照）

| 通过率 | section | 通过/总数 | 主要缺口 |
|--------|---------|-----------|---------|
| 100% | Paragraphs / Blank lines / Tabs / Precedence / Soft line breaks / Textual content | 24/24 | — |
| 100% | HTML blocks / Raw HTML（冒烟级） | 64/64 | 仅"解析不崩" |
| 100% | Hard line breaks | 15/15 | — |
| 96% | Lists | 26/27 | 1 例 |
| 69% | Block quotes | 22/25 | 嵌套/多行引用（§9 P1 缺口） |
| 69% | List items | 33/48 | 起始编号、松紧列表语义 |
| 65% | Entity and numeric character references | 11/17 | 实体解码不完整 |
| 54% | Setext headings | 14/27 | `===`/`---` 下划线标题误判分割线 |
| 54% | ATX headings | 15/18 | 边角（`#5 bolt`、空格变体） |
| 54% | Autolinks | 8/19 | `<url>` 不识别 |
| 53% | Thematic breaks | 10/19 | `***`/`___` 变体 |
| 45% | Fenced code blocks | 13/29 | 信息串边角、嵌套栅栏 |
| 37% | Link reference definitions | 10/27 | 不支持引用定义 |
| 36% | Emphasis and strong emphasis | 47/132 | `_` 边界、嵌套/优先级（最大失分项） |
| 25% | Indented code blocks | 3/12 | 4 空格缩进代码块（`trimLeft` 吃缩进） |
| 24% | Links | 22/90 | 内联链接边角 + 引用式链接全缺 |
| 18% | Code spans | 4/22 | 多反引号 code span |
| 14% | Images | 3/22 | 图片语法同链接，边角+引用式全缺 |
| 12% | Backslash escapes* | 12/13* | *谓词仅查 emphasis 形状，弱覆盖 |

*注：`Backslash escapes` 当前谓词较弱（仅当规范期望 emphasis 时检查），通过数偏乐观；spec 升级谓词后基线需人工确认更新。

## 3. Ratchet 守门规则

- **守门测试**：`flutter_app/test/parser/commonmark_conformance_test.dart`
  - 任何 section 通过数 **低于基线** → 测试失败（禁止回归）
  - 高于基线 → 通过并打印提示（鼓励收敛）
  - **崩溃零容忍**：任何 spec 输入导致 parser 抛异常 → 直接失败
- **基线再生**：`dart run tool/gen_spec_baseline.dart`（数值只能人工确认后上调，禁止下调）
- **用例再生**（spec 升级时）：`dart run tool/gen_spec_examples.dart`
- **许可**：spec.txt / examples.json 为 CC-BY-SA 4.0（© John MacFarlane），见 `spec/README.md`

## 4. 收敛路线（把失分项排进 roadmap）

按"修复性价比 = 用例数 × 日常频率"排序：

| 优先级 | 缺口 | 潜在收益（用例） | 对应规划 |
|--------|------|-----------------|---------|
| P0 | 多反引号 code span | +18 | §9 P2 |
| P0 | `<url>` autolink | +11 | §9 P2 |
| P1 | 嵌套/多行引用块 | +3~10 | §9 P1（4.3 修订） |
| P1 | Setext 标题识别 | +13 | §9 P2 |
| P1 | 有序列表起始编号 | +10~15 | §9 P1 |
| P2 | 缩进代码块（4 空格） | +9 | §9 P2（需 ADR-0004 修订） |
| P2 | emphasis `_` 边界与优先级 | +30~60 | 最大单点收益，parser 核心改造 |
| P3 | 链接/图片引用定义 | +35~40 | 独立特性 |

全部收敛后理论上限约 85-90%（剩余为 HTML 输出语义级差异，AST 形态无法逐字对齐，属谓词天花板）。
