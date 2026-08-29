---
name: office-consumer
description: >-
  Office/PDF 消费端验证 —— 用 wpscli / officecli / pdfinfo 验证 Tafcm 导出的
  DOCX/PDF 在真实 Office 兼容环境可打开、可转换、内容保真（公式不丢）。
  当需要验证"导出产物在消费端是否正确"、排查 Word/PDF 导出兼容性、
  或跑 FFX word capability 消费端证据链时使用。
---

# Office/PDF 消费端验证（wpscli / officecli / pdfinfo）

## 背景

Tafcm 的 Word/PDF 导出由自研 OOXML/SVG 管线生成，产物是否正确必须经过
**真实消费端**验证（模拟器/本机自检 ≠ 真实 Office 打开）。本 skill 封装
FFX harness consumers 的调用方式，产出统一证据（exit_code + summary + issues）。

工具探测（FFX 内置，勿手动找路径）：
- `wpscli`：WPS 命令行（word2pdf 转换 / pdfinfo 元数据）
- `officecli`：OfficeCLI（view screenshot 视觉捕获 / view issues 结构化问题）
- `pdfinfo`：poppler pdfinfo 优先，回退 wpscli pdfinfo

## 快速验证（推荐入口）

```bash
# 方式一：FFX consumer 模块（归一化输出 {exit_code, summary, issues}）
cd tools/ffx-cli
python -m pytest cli_anything/ffx/tests/test_consumers.py -q        # 13 用例自检

# 方式二：Python 直接调用（产物在手上时）
python - <<'PY'
from cli_anything.ffx.harness.consumers import wpscli, officecli, pdfinfo
r = wpscli.word2pdf("cap_word_fix.docx", "out.pdf")   # 真实转换
print(r.exit_code, r.summary, r.issues)
PY
```

## 标准证据链（Word 导出 → 消费端验证）

```text
导出 DOCX（WordExporter / 既有 corpus）
  ├→ wpscli.word2pdf        → 真实 Office 兼容转换 → PDF
  │    └→ wpscli.pdfinfo     → 消费端分页/扫描元数据（page_count）
  ├→ officecli.view_screenshot → 第 1 页 PNG（视觉捕获，Agent/人工审阅）
  └→ officecli.view_issues   → 结构化问题清单（Agent 可自愈）
```

## 判定口径

| 结果 | 含义 |
|------|------|
| `exit_code == 0` + `issues == []` | 消费端验证通过 |
| `exit_code == 127` | **工具缺失**（ENV_MISSING）≠ 产品失败——补装 wpscli/officecli 后重跑 |
| `exit_code != 0` | CLI 调用失败（rc 为 CLI 真实码；2 = officecli 输出 schema 违规） |
| `issues` 非空 | 结构化问题（如公式缺失 missing_in_consumer、officecli issues 列表） |

**关键纪律**：
- 产物成功 ≠ 功能正确——DOCX 能打开 ≠ 公式语义在消费端保留；必须查
  `pdf2txt` 文本中公式 fallback 片段（`^`/`_`/`\` 特征）是否出现。
- wpscli 渲染截图需会员（CAP-WORD-F 曾受阻）——视觉捕获优先用 officecli。
- 不重实现引擎：只调用外部 CLI + 归一化，任何引擎逻辑回 FFX core。

## 相关

- 设计：[docs/architecture/AGENT-ENGINEERING.md §3.4](../docs/architecture/AGENT-ENGINEERING.md)
- 调研：[docs/archive/spikes/OFFICECLI-RESEARCH.md](../docs/archive/spikes/OFFICECLI-RESEARCH.md)
- 实现：[tools/ffx-cli/cli_anything/ffx/harness/consumers/](../tools/ffx-cli/cli_anything/ffx/harness/consumers/)
- 测试：[tools/ffx-cli/cli_anything/ffx/tests/test_consumers.py](../tools/ffx-cli/cli_anything/ffx/tests/test_consumers.py)
