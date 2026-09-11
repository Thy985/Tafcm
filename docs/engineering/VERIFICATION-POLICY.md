# Verification Policy（验证纪律）

**定位（L2 工程真相）**：验证/测试纪律单一真相——什么算通过、什么证据等级、什么禁止。
**数据源**（历史完整文档，已归档保留）：
- [VERIFICATION-POLICY-source-e2e.md](VERIFICATION-POLICY-source-e2e.md)（E2E 测试计划：Core + Extended + Patrol）
- [VERIFICATION-POLICY-source-gap.md](VERIFICATION-POLICY-source-gap.md)（测试缺口计划）
- [VERIFICATION-POLICY-source-skip.md](VERIFICATION-POLICY-source-skip.md)（skip 登记）
- [GATE-REPORT.md](GATE-REPORT.md)（Phase 3.10 Final Gate G0-G12）

---

## 门禁基线（与 CI 一致）

| 门禁 | 命令 | 备注 |
|------|------|------|
| Analyze | `flutter analyze --no-fatal-infos --fatal-warnings` | 裸 analyze 只把 warning 当 info，本地可能漏检 |
| Test | `flutter test`（全量，~1700 用例） | Windows 本机受 cmd 命令行长度限制 → 分块跑 |
| Build | `flutter build apk --debug` + `flutter build web` | 两平台 |
| Contract Sync | `ffx contract-sync` | contracts/ 与矩阵自洽 |
| CLI 测试 | `cd tools/ffx-cli && python -m pytest cli_anything/ffx/tests/` | 170+ 用例 |

## 证据等级（Evidence Strength，RUN-013 冻结）

```
synthetic < test_runtime < production_runtime < virtual_device_runtime
< physical_device_runtime < visual < human_confirmed
```

- Emulator PASS ≠ release gate PASS（语义偷换禁止）
- `contracts/formula.json` achieved 已含 physical_device_runtime（真机 zorn 4/4）

## 回归纪律

- 每个发现 bug → regression asset（BUG case 包，见 [regression/](../regression/)）
- 回归判定用 baseline failure set + fingerprint diff（四层 Failure Identity）
- 既有失败 ≠ 新增回归

## E2E 发布门（Release Gate，U7 制度化）

> 来源：[TEST-SYSTEM-UPGRADE-PLAN.md](TEST-SYSTEM-UPGRADE-PLAN.md) §3.7（学 SoloMD dogfooding 门）。
> integration_test 不在 CI 主链（真机/模拟器资源限制），因此**发布动作前强制执行**本清单，不靠人工记忆。

**触发条件**（任一满足即必跑）：
- 打 release tag 前
- 发布 APK / 内测包前
- 合并标记为 `release-candidate` 的 PR 前

**必跑清单**（全轮 `integration_test/` ≈ 18min；Gradle `Connection reset` 重跑即过，见 AGENTS.md §13.2）：

| # | 冒烟项 | 对应测试 | 覆盖的致命面 |
|---|--------|---------|-------------|
| 1 | 外部分享 .md 打开（微信/QQ → 本应用） | external file 链路 | ACTION_VIEW 冷/热启动 |
| 2 | 公式渲染（行内 + 块级 + PDF 导出） | cap_e6 / formula 套件 | WebView 渲染链 |
| 3 | Mermaid 图表渲染 | mermaid 套件 | WebView 共享契约 |
| 4 | 导出三格式（PDF/Word/TXT）+ 进度浮层收尾 | phase35_export_e2e | 导出链 + #248 超时面 |
| 5 | 自动保存恢复（编辑 → 杀进程 → 重开） | phase34_persistence | 数据完整性 |

**记录要求**：每次发布门执行结果（PASS/FAIL + runner 设备 + 日期）登记到 `docs/evidence/` 对应 release 条目；FAIL 时按回归纪律走 baseline failure set 判定，禁止带病发布。

## 禁止

- 删除测试以通过 CI（必须修代码）
- UI 层直接展示异常 detail / stack
- 新增全局静态状态（先例：MermaidService._cache 已加 clearCache）

详见 [DEVELOPMENT-RULES.md](DEVELOPMENT-RULES.md) 与 [AGENTS.md](../../AGENTS.md)。
