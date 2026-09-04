# Tafcm Verification Map（2026-09-04 首版）

> 目标系统：Tafcm Android APK。从"验证需求 → 当前覆盖 → Gap → 责任 Agent"出发。
> 状态：proven / conditional / partial / unknown / blocked_by_*。

## 总览
**Tafcm 的核心验证缺口一句话：APK 一直被构建、从未被运行。** CI 产出 debug APK 并上传 release，但无任何模拟器/真机 runtime 验证；integration_test 全部为 widget 级（testWidgets，host 内存执行），不涉及真实 Android runtime。

## Map

| 维度 | status | existing_tests | evidence_strength | known_gaps | responsible |
|---|---|---|---|---|---|
| build (APK) | ✅ proven | ci.yml `build-android`（`flutter build apk --debug`）+ release v0.1.1 双 APK | production | 仅 debug 签名构建；release 签名流程未在 CI 自动化 | Cline/workflow |
| unit | ✅ proven | `flutter test` 129 passed | production | — | Cline |
| golden | ✅ proven | `flutter test --tags golden` 29 passed（Linux 基线） | production | 仅 Linux 基线，非设备渲染 | Cline |
| ADI E2E | ✅ proven | ci.yml `adi-e2e`（Dart 协议） | production | — | Cline |
| integration (widget 级) | ✅ proven | integration_test/ 40+（phase33-35 系列）`testWidgets` | production | 全是 host widget 级，非 device 级 | Cline |
| emulator_runtime | ❌ blocked/gap | CI 无模拟器 job；本地无 /dev/kvm | env-probe | **APK 从未在 Android 运行** | CI 可加 android-emulator-runner；Doubao 环境 blocked_by_environment |
| ui_interaction (device) | ❌ gap | 无 | — | 真实触控/交互/IME 未验证 | 模拟器 job / 真机 / Web 代理 |
| visual (device) | ❌ gap | golden 仅 Linux 基线 | — | 设备真实渲染（字体/公式/WebView/主题）未验证 | 真机截图 / Web 代理截图 |
| state_transition (device) | ⚠️ partial | widget 级 phase34/35 覆盖状态链 | test_runtime | device 级状态迁移未验证 | widget 级 proven；device 级 gap |
| error_handling (device) | ⚠️ partial | test/error + adi_fault_injection（widget 级） | test_runtime | 崩溃/ANR/系统级异常未验证 | device 级 gap |
| recovery (device) | ⚠️ partial | widget 级部分 | test_runtime | 进程重启/数据完整性未验证 | device 级 gap |
| physical_device | ❌ blocked | tools/adi/realdevice（接口预留，无执行） | — | 真机验证完全空白 | Human + 设备 |
| regression | ✅ partial | docs/regression + golden 基线 + FINDINGS | — | 无 device 级回归资产 | Cline proven |
| evidence | ✅ partial | docs/evidence + CI artifacts | — | 无 device 级 evidence（截图/真机日志） | — |

## 高价值 Gap（进入 Agent Discovery）
1. **APK runtime 完全空白**（emulator + device interaction + visual）—— impact 高、cost 中（CI 模拟器）、无 workaround
2. **device 级视觉验证**（公式/Mermaid/主题在真实渲染环境）—— 与 #216/#234（公式导出空白）直接相关，真机 PoC 是第一排查项
3. **真机 state_transition / recovery**（外部文件保存 #240、长文档性能 #245-250 的 device 侧验证）

## 各 Agent 可补能力（Evidence-backed）
- **Cline（CI）**：build/unit/golden/ADI/widget-integration **已 proven**；可新增 `android-emulator-runner` job 补 emulator_runtime + smoke UI（需 workflow 变更，走 Human 合入）
- **Doubao（Cloud Computer）**：
  - APK 下载 + 静态审计（manifest/权限/签名/资源/体积/依赖库）→ **proven**（A-01）
  - Flutter Web 代理 UI/视觉验证 → **条件可行**（需 setup flutter + build web + 服务器；浏览器感知 D-01 已 proven 为底座）
  - Android 模拟器 → **blocked_by_environment（无 KVM）**
  - 真机 → blocked（需 Human 设备）
- **Cross-Agent 组合**：CI build APK → Doubao 静态审计 +（setup 后）Web 代理 UI → 真机 device 验证 → Evidence 回流入 regression

## 建议架构（3 层补缺口）
1. **L2 CI 模拟器**（低成本）：`android-emulator-runner` 跑 device 级 smoke/integration —— 补 emulator_runtime + 部分 UI
2. **L3 Doubao Web 代理**（中成本）：build web + 浏览器验证 UI/视觉/状态 —— 补 device 级视觉/交互（同一 widget 树代理）
3. **L4 真机**（Human）：physical device 完整验证（#216/#240/#245-250 的 device 侧收口）
