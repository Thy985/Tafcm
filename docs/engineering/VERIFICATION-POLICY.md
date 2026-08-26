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

## 禁止

- 删除测试以通过 CI（必须修代码）
- UI 层直接展示异常 detail / stack
- 新增全局静态状态（先例：MermaidService._cache 已加 clearCache）

详见 [DEVELOPMENT-RULES.md](DEVELOPMENT-RULES.md) 与 [AGENTS.md](../../AGENTS.md)。
