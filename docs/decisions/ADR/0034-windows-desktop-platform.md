# ADR-0034: Windows 桌面端首个平台决策（MVP 边界与 CI / 测试 / 降级策略）

- **状态**: Proposed（待 Human Owner 签字；签字后 Phase 4.1 按本 ADR 落地）
- **日期**: 2026-10-12
- **关联**: ROADMAP Phase 4.1 · ADR-0006（CI GitHub Actions，曾明确"iOS/Windows 暂不进 CI"） · ADR-0033（产品定位收敛——移动端创作优先） · DEBT-021（快捷键 / 打字机，排 Phase 4 Desktop） · `docs/contracts/phase3.3-task-contract.md §6.6`（E2E 平台约束）

## 背景

Phase 3 系列全部收尾、v0.2.0+3 已对外发布，项目进入阶段间空档期。ROADMAP Phase 4.1 早已列出"桌面端适配（macOS / Windows / Linux）"，但从未立项——此前 ADR-0006 明确"iOS / Windows 暂不进 CI"（GitHub 免费额度理由），Phase 3.3 Task Contract §6.6 也把"Windows 桌面"列为未启用平台（`.metadata` 未登记，无 runner，无法跑 `flutter test integration_test`）。

现状事实（2026-10-12 实测）：

| 项 | 现状 |
|---|---|
| `flutter_app/windows/` | 不存在（无原生工程） |
| `flutter_app/.metadata` | 仅登记 android / ios / web |
| CI workflow | 无 Windows build job |
| Dart 层平台分支 | 0 处（`grep -r "Platform.is\|TargetPlatform" flutter_app/lib/` 无匹配） |
| Windows 运行时依赖 | `flutter_inappwebview` 6.x 家族未 pin windows 平台实现；`file_picker` / `share_plus` Windows 平台能力未在本项目验证 |
| Golden 基线 | Linux CI 唯一基线；Windows 本地不比对（`GOLDEN-CI-001`） |
| integration_test | Android Emulator 为当前唯一可行平台（Level 1 每 PR / Level 2 里程碑） |

**关键观察**：Dart 层已完全平台无关——全 `lib/` 无一处 `Platform.is*` / `TargetPlatform` 分支，跨平台迁移的阻力几乎全部落在原生层（`flutter create . --platforms=windows`）+ 平台插件的运行时兼容性 + CI runner 选型。

## 决策

引入 **Windows 桌面端 MVP**，范围严格限定为"能构建、能启动、能完成核心编辑链路"，不承诺与移动端对齐。共 6 条子决策：

### D1 平台范围：Windows 先行，macOS / Linux 不在本 ADR 范围

- 只启用 `windows/`；`macos/` / `linux/` 不新建（Phase 4.1 后续 ADR 独立处理，避免一次铺开 3 平台把原生工程量与 CI 时间都推爆）。
- 与 ADR-0033 的"移动端创作工具"定位不冲突：Windows MVP 定位为**桌面端写作体验的补集**（物理键盘 + 大窗口 + 大文件编辑），不是"桌面 Typora 克隆"，也不改变 ADR-0033 的用户侧三维（T/F/M）排序依据。

### D2 CI 策略：新增 `build-windows` job，不作为每 PR 必需门槛

- 在 `.github/workflows/ci.yml` 新增 `build-windows` job，`runs-on: windows-latest`，`flutter build windows --release --no-pub`，产物上传为 `windows-build` artifact。
- **不作为每 PR 必需门槛**：与 `android-device` job 同策略（`workflow_dispatch` 手动 + `changes` 路径过滤双条件触发），仅当 `flutter_app/windows/**` / `flutter_app/pubspec.yaml` / `.github/workflows/ci.yml` 变更时才跑。
- 理由：GitHub Actions windows-latest runner 冷启动 + Flutter 依赖缓存缺失 → 单 job 预计 10-15 min；若每 PR 都跑，会把当前 CI 总时长从 ~8 min 推到 ~20 min，代价与收益（MVP 阶段几乎每次都会跑）不成比例。
- ADR-0006 的"iOS / Windows 暂不进 CI"结论部分过时（现改为"Windows 进 CI 但不每 PR 跑"），**保留 ADR-0006 主结论（额度约束下的取舍思路）不变**，本 ADR 只覆盖 Windows 一个平台。

### D3 E2E 策略：Windows 不接管 `integration_test`，维持 Android Emulator 独占

- Level 1 Framework E2E（每 PR）仍由 Android Emulator 承担，Phase 3.3 Task Contract §6.6 的临时结论**继续有效**。
- Windows 桌面端冒烟验证走**本地手动 + 里程碑**双轨：
  - 里程碑：Windows MVP 关闭前 Human Owner 在本地 Windows 机器上跑一次 `flutter run -d windows` 手动冒烟（启动 / 打开种子文档 / 编辑 / 导出），结果记入 `docs/releases/phase4.1-windows-mvp-verification-report.md`。
  - 未来：若 `flutter_inappwebview` 家族在 Windows 上稳定，可考虑引入 `patrol` 的 Windows support（当前版本不支持，需跟踪 patrol changelog）；不阻塞本 ADR。
- 不为 Windows 单独维护 `integration_test`——Dart 层已平台无关，同一份测试在 Android 与 Windows 上的语义等价性由 `flutter test`（unit/widget，不含 integration）守门。

### D4 功能降级清单（MVP 明确不实现，登记为 Phase 4.x 后续项）

| 功能 | MVP 处理 | 替代方案 | 后续 ADR |
|---|---|---|---|
| 外部 .md 打开（ACTION_VIEW Intent） | 不实现 | 菜单栏 / 拖放 / "打开文件"按钮 | 本 ADR 后续（Phase 4.2 候选） |
| `ExternalFileService` MethodChannel | 保留调用但 Windows 无对应实现，`getInitialUri` 返回 null → 静默跳过（现有 catch 已覆盖） | 无 | 无 |
| `share_plus.shareXFiles`（分享） | 保留但 Windows 走系统文件选择器 | 用户手动"另存为" | 无 |
| `file_picker`（图片插入） | Windows 走系统文件对话框（能力存在，需验证 8.x 版本行为） | 无 | 无 |
| `flutter_inappwebview`（公式 SVG / Mermaid） | **MVP 硬依赖**——见 D5 | 无（核心能力） | 无 |
| 键盘快捷键（Ctrl+Z/B/I 等） | 不做（DEBT-021） | 无（MVP 只做鼠标 / 触屏兼容的编辑面） | Phase 4 Desktop Enhancement（DEBT-021） |
| 打字机模式 / 多窗口 / 全局搜索 | 不做 | 无 | Phase 4 后续 ADR |
| 自动更新（electron-updater / msix） | 不做 | 手动下载 release zip | Phase 4 后续 ADR |

### D5 运行时依赖：WebView2 Runtime 为硬前置

- Windows 桌面端跑通公式 SVG 与 Mermaid 图**硬依赖 Microsoft Edge WebView2 Runtime**。
- Windows 10 1803+ 与 Windows 11 默认内置（Evergreen 通道随系统更新）；老机器（Win7 / Win8 / 早期 Win10）需手动安装。
- **MVP 决策**：不在安装包内捆绑 WebView2 固定版本（会增加 ~100MB 包体积 + 维护负担）；改为在 `README.md` Windows 安装节 + 应用内"首次启动检测"提示用户从 [microsoft.com/edgeworks](https://developer.microsoft.com/en-us/microsoft-edge/webview2/) 下载 Evergreen Bootstrapper。
- 若 `flutter_inappwebview_windows` 平台实现在本项目验证失败（如 `evaluateJavascript` 超时 / `loadFile` 路径错误），MVP 降级路径为"公式行内走 `flutter_math_fork` 纯 Dart 渲染 + Mermaid 显示源码占位"，与 Android 端 swiftshader 环境的降级策略一致（`kMermaidHostEnabled=false` 编译期开关）。

### D6 回滚策略

- 回滚 = 删除 `flutter_app/windows/` 目录 + 从 `.metadata` 移除 windows 条目 + 移除 `build-windows` job。所有动作幂等，无残留。
- 回滚触发条件：
  1. Windows 构建在 CI 与本地都连续 3 次失败且非平台插件问题（本项目 Dart 层 bug 影响全平台）
  2. WebView2 Runtime 依赖把 MVP 拖成"半数 Windows 用户装不上"
  3. Windows 平台出现阻塞级渲染 bug（WYSIWYG 编辑面在 Windows 上严重错乱），短期内无法修复

## 动机

- **Dart 层零平台耦合**：`grep -r "Platform.is\|TargetPlatform" flutter_app/lib/` 无匹配——跨平台迁移几乎无 Dart 层重构成本，是"最低风险新增平台"的窗口期。
- **不推迟**：Phase 3 已收尾、v0.2.0+3 已发布，Phase 4 未启动。空档期做 Windows MVP 的边际成本低于未来在功能更多时再迁移（每新增一个平台相关分支都会成倍增加迁移成本）。
- **不扩张**：本 ADR 明确不铺 macOS / Linux、不承诺快捷键 / 多窗口 / 自动更新，把 MVP 收缩到"能跑通核心链路"，避免"多平台立项"变成"多平台功能对齐工程"。
- **CI 代价可控**：Windows job 走 `changes` 路径过滤 + 手动触发，与现有 `android-device` job 同策略，不增加每 PR 的 CI 时长与免费额度消耗。
- **产品定位不冲突**：ADR-0033 的"移动端创作优先"是**排序依据**，不是"不做桌面"的禁令；桌面端写作体验（物理键盘、大窗口）是学术写作用户群体的合理诉求，与移动端形成互补而非分裂。

## 后果

### 正向

- 桌面端写作体验可用（打开 / 编辑 / 导出 / 公式 / Mermaid 图表）
- Dart 层继续 0 平台耦合，未来 macOS / Linux 迁移成本不变
- 用户群扩展：物理键盘用户对学术写作是刚需（论文 / 讲义 / 会议记录）

### 负向 / 风险

- **包体积**：Windows x64 release 构建预计 30-60 MB（含 NotoSerifSC / NotoSansSC / CascadiaMono 三个 TTF 字体），显著大于 Android APK（~20 MB）
- **CI 时间**：`build-windows` job 手动触发时预计 10-15 min（GitHub windows-latest 无 Flutter 预热缓存）
- **WebView2 依赖**：老 Windows 版本需手动安装（MVP 决策不捆绑，见 D5）
- **`flutter_inappwebview_windows` 兼容性未验证**：这是 MVP 最大技术风险（公式 SVG + Mermaid 的核心路径），需第一个 PR 就验证
- **golden 基线**：Windows 上字体渲染可能与 Linux CI 基线有微小差异（`GOLDEN-CI-001` 前科），但 Windows 上本就不跑 golden test（本地跳过 + CI Linux 唯一基线），无回归风险
- **`file_picker` / `share_plus` Windows 实现**：未在该项目验证过，可能有 API 差异或行为差异，需 MVP 阶段实测
- **`share_plus` 在 Windows 上的行为**：调用系统文件选择器可能不是用户期望的"分享"体验——MVP 阶段接受此降级（D4 已登记）

## 替代方案

1. **一次铺 macOS + Windows + Linux 三平台**——否决：原生工程量 ×3、CI 时间 ×3、平台插件兼容性 ×3；MVP 阶段风险与收益不成比例。
2. **只做 Linux**——否决：用户群体小、CI 免费额度紧张、Dart 层收益与 Windows 等价。
3. **改用 Electron / Tauri 重写**——否决：与 Phase 3 已投入的 Flutter WYSIWYG 编辑面完全不兼容（重做编辑面 = 推翻 ADR-0007 / 0019 / 0020）。
4. **保持移动-only，不做桌面**——否决：Phase 4.1 已立项且 Dart 层 0 耦合的窗口期不会一直开；未来做桌面端成本只会更高。
5. **Windows MVP 也做 keyboard shortcuts + 打字机模式**——否决：与 DEBT-021 冲突，会把 MVP 拖成"桌面增强工程"；快捷键 / 打字机留 Phase 4 Desktop Enhancement 独立 ADR。

## 边界

- 本 ADR 只定义 Windows MVP 的**决策与边界**，不定义具体实现步骤（具体 PR 拆分由 Phase 4.1 Task Contract 落地）。
- 本 ADR **不**修改 ADR-0033（产品定位）、ADR-0006（CI 主结论）、ADR-0031（品牌）——只在 Windows 单一平台范围内做增量决策。
- 本 ADR **不**承诺 macOS / Linux / Web 桌面（PWA 已有，非本 ADR 范围）。
- 本 ADR **不**引入键盘快捷键 / 打字机模式 / 多窗口 / 自动更新——这些归 DEBT-021 或 Phase 4 后续 ADR。
- 本 ADR **不**改变 golden 基线策略（Linux CI 唯一基线，Windows 本地不比对）。
- 本 ADR **不**改变 integration_test 平台分工（Android Emulator 独占，Windows 走本地手动冒烟）。

## Phase 4.1 落地里程碑建议（非强制，供 Human Owner 参考）

| 里程碑 | 内容 | 依赖 |
|---|---|---|
| M1 | `flutter create . --platforms=windows .` 生成原生工程 + 首次 `flutter build windows --release` 通过 | 无 |
| M2 | WebView2 Runtime 验证：`flutter_inappwebview_windows` 平台实现能加载 `assets/mermaid_renderer.html` + 完成一次 `evaluateJavascript` 往返 | M1 |
| M3 | `file_picker` / `share_plus` Windows 实测 + 降级行为登记 | M1 |
| M4 | `build-windows` CI job（`changes` 路径过滤 + 手动触发）+ 首个 Windows 构建产物 artifact | M1 |
| M5 | 本地手动冒烟报告（`docs/releases/phase4.1-windows-mvp-verification-report.md`） | M2-M4 |

**MVP 关闭判据**：M1-M5 全部完成 + Human Owner 本地 Windows 手动冒烟通过（打开种子文档 → 编辑 → 导出 PDF / DOCX / TXT）。

## 相关

- [ADR-0006](0006-ci-github-actions.md) — CI GitHub Actions（ADR-0006 主结论保留，本 ADR 仅覆盖 Windows 增量）
- [ADR-0033](0033-product-positioning-convergence.md) — 产品定位收敛（本 ADR 不改变排序依据）
- [docs/contracts/phase3.3-task-contract.md §6.6](../../contracts/phase3.3-task-contract.md#L566-L581) — E2E 平台约束（继续有效）
- [docs/engineering/ENGINEERING-BASELINE.md](../../engineering/ENGINEERING-BASELINE.md) — DEBT-021（快捷键 / 打字机）
- [docs/ROADMAP.md Phase 4](../../ROADMAP.md) — Phase 4 任务列表
