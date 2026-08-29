# AGENTS.md — AI 协作开发规范

> 本文件是 Tafcm 项目对所有 AI 协作开发者（含 TRAE Agent / Claude Code / Cursor / 人工协作者）的强制规范。
> 所有 PR 必须通过本文档的检查项才能合并。

---

## 0. 项目愿景与定位

**Tafcm**（Typeset · Agent-native · Formula-aware · CLI-native · Markdown-first，见 [ADR-0031](docs/decisions/ADR/0031-rebrand-tafcm.md)）的目标是演进为 **移动端 Typora 类产品**：

- 不是"带预览的 Markdown 编辑器"，而是 **所见即所得（WYSIWYG）** 编辑器
- 不是"桌面端 Typora 的功能搬运"，而是 **手机优先（mobile-first）** 的重新设计
- 不是"通用笔记 App"，而是 **以公式 / 图表 / 学术写作为特色** 的专业写作工具
- 不是"像 Obsidian 那样只能在自家 Vault 内查看"，而是 **任意来源 .md 文件即开即看** 的便携查看器

**当前阶段定位**：Phase 0-2 及 2.8/2.9 已关闭；Phase 3.0-3.7（EditorShell / WYSIWYG / 输入体验 / TOC·主题·导出·文件树 / 设计系统对齐 / 公式渲染 / E2E / 可观测）已全部完成并合入 main；Phase 3.8 ADI v0.1/v0.2 已合入（v0.3 拆至 ADR-0026）；Phase 3.10 FFX Verification Orchestrator 经 Final Gate G0-G12 全通过后关闭；**Phase 3.11 Capability Hardening Loop 已于 2026-08-22 经 Human Owner 判定关闭**。2026-08-25 治理轮（PR #167-#172）完成 .gitignore / preflight / 根目录清理 / 分支审计 / 本清单同步。
**当前位置**：Phase 3 系列收尾完毕，Phase 4 未启动，处于**阶段间空档期**。产品侧已知缺口以 [PHASE3.10-TYPORA-GAP-ANALYSIS.md](docs/product/TYPORA-GAP-ANALYSIS.md) §3-4 为准（表格单元格可视化编辑 / HTML 导出 / 源码视图切换等）+ 未启动的 3.4.10 选区格式化菜单；下一步立项由 Human Owner 决定。  
**当前阶段禁区**：空档期内不启动新大阶段功能；架构决策一律先落 ADR；UI Prototype Freeze 已随 Phase 3 UI 重写完成而结束（ROADMAP Phase 0 定义"UI 在 Phase 3 重新实现"已发生）。  
*（本节由 docs/align-phase-status PR 对齐至 2026-08-26 实况；§6.5 等历史阶段条款如与本节冲突，以本节为准。）*

---

## 1. 项目架构原则

### 1.1 六层分层架构（严格自上而下依赖）

```
presentation/    UI 组件、屏幕、主题
      ↓
providers/       全局 Riverpod Provider
      ↓
domain/          业务领域（导出服务、业务 Provider）
      ↓
data/            数据模型（Document / Template）
      ↓
core/            基础设施（parser / renderers / services / router / utils）
      ↓
main.dart        App 入口
```

**强制规则**：
- `core` 不允许反向 import `presentation` / `domain` / `providers`
- `data` 不允许 import `core` 之外的业务代码
- `presentation` 不允许跨过 `domain` / `providers` 直接调用 `core` 的服务（除路由、常量等纯工具）
- 循环依赖零容忍

### 1.2 单一职责

一个 `.dart` 文件 = 一个 class / 一个主题 / 一个 Provider 簇。  
文件超过 **400 行** 必须拆分。

### 1.3 显式依赖

- 服务类构造函数注入，不写 `class.service()` 风格的全局静态方法
- 例外：现有 `MarkdownExporter` / `PdfExporter` / `WordExporter` 已是 facade 静态，重写前不动
- 测试时通过 `MarkdownExporter.register({...})` 注入 fake（见 [export_service.dart:67-83](file:///d:/Projects/Active/math2/flutter_app/lib/domain/services/export_service.dart#L67-83)）

---

## 2. Flutter 编码规范

### 2.1 命名

| 类型 | 规则 | 示例 |
|------|------|------|
| 类 / 枚举 / typedef | UpperCamelCase | `DocumentElement`、`ExportFailure` |
| 文件名 | snake_case.dart | `markdown_parser.dart` |
| 方法 / 变量 | lowerCamelCase | `parseInline`、`isDarkMode` |
| 常量 | lowerCamelCase 或 UPPER_SNAKE_CASE（限 static const） | `maxHistorySize`、`_kHtml` |
| 私有 | 前缀 `_` | `_PendingLatex`、`_dispatchWaiting` |
| Provider | `xxxProvider` 后缀 | `documentsProvider`、`darkModeProvider` |

### 2.2 现代 Dart 特性使用（鼓励）

- sealed class 用于 AST / 状态联合（已在 [document.dart](file:///d:/Projects/Active/math2/flutter_app/lib/data/models/document.dart) 落地）
- 模式匹配 `switch` 替代 if-else 链（已在 [preview_content.dart:80-102](file:///d:/Projects/Active/math2/flutter_app/lib/presentation/widgets/preview_content.dart#L80-102) 落地）
- records 用于多值返回（已在 `ExportFailureInfo` 落地）
- 空安全：禁止 `!` 强制解包，除非同一行内已 null 检查

### 2.3 注释

- **dartdoc** `///` 用于 public API（公开给其他模块调用的方法）
- **普通** `//` 用于实现细节
- **TODO 格式**：`// TODO(<name>): <desc> —— 见 <ticket/url>`
- 禁止无意义注释（如 `// constructor`）
- 中文注释允许，但 public API 的 dartdoc 优先英文（便于跨团队协作）

### 2.4 文件头

每个 `.dart` 文件必须有 1-3 行 `///` 顶部文档，说明该文件职责。  
参考 [export_service.dart:1-19](file:///d:/Projects/Active/math2/flutter_app/lib/domain/services/export_service.dart#L1-19) 的写法。

### 2.5 import 顺序

```dart
// 1. Dart SDK
import 'dart:async';
import 'dart:io';

// 2. Flutter / 第三方
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// 3. 项目内（按相对路径，不混用 package:）
import '../../core/constants/app_constants.dart';
import '../../data/models/document.dart';
```

---

## 3. 状态管理规范（Riverpod）

### 3.1 Provider 选择决策树

```
需要异步数据？
  └ 是 → FutureProvider / AsyncNotifierProvider
  └ 否 → 需要修改状态？
          └ 是 → StateNotifierProvider（业务状态）/ StateProvider（UI 状态）
          └ 否 → Provider（依赖注入）
```

### 3.2 命名与归属

- 业务级 Provider 放 `domain/providers/`
- UI 全局状态放 `providers/`
- **禁止在多个文件定义同名 Provider**（当前 [providers/providers.dart](file:///d:/Projects/Active/math2/flutter_app/lib/providers/providers.dart) 与 [providers/editor_providers.dart](file:///d:/Projects/Active/math2/flutter_app/lib/providers/editor_providers.dart) 重复定义 `sharedPreferencesProvider` / `darkModeProvider`，是 bug，待 P0 重构修复）

### 3.3 状态不可变性

- `StateNotifier<S>` 的 `S` 必须是不可变类型
- 集合修改用 `copyWith` 或新对象，禁止 `state.list.add(...)`
- 已有范本：[data/models/document.dart:108-122](file:///d:/Projects/Active/math2/flutter_app/lib/data/models/document.dart#L108-122) 的 `copyWith`

### 3.4 Provider dispose

- 资源持有型 Provider（WebView、Stream、Timer）必须实现 `autoDispose` 或显式清理
- 当前 [editor_screen.dart:51-65](file:///d:/Projects/Active/math2/flutter_app/lib/presentation/screens/editor_screen.dart#L51-65) 在 `dispose` 中清空静态缓存是 hack，待 WYSIWYG 重构后移除

---

## 4. 数据访问规范

### 4.1 单一真相源（目标状态，当前未达成）

**目标**：`.md` 文件作为文档唯一存储，废弃 `formula_fix_documents.json` 与 `SharedPreferences['pref_last_content']`。

**理由**：见 [docs/decisions/ADR/0003-storage-single-source-md-files.md](file:///d:/Projects/Active/math2/docs/decisions/ADR/0003-storage-single-source-md-files.md)。

**过渡期规则**：在 ADR-0003 执行前，**禁止新增第四套存储**。

### 4.2 服务层访问

- UI 不直接调 `DocumentService`，必须通过 `domain/providers/document_provider.dart` 的 Provider
- 例外：`EditorScreen` 当前直接调 `FileService` 是历史遗留，重构时下沉到 Provider

### 4.3 编码兜底

- 所有从外部读取的字节流必须走 [file_service.dart:13-41](file:///d:/Projects/Active/math2/flutter_app/lib/core/services/file_service.dart#L13-41) `decodeBytesAuto`
- 禁止直接 `utf8.decode(bytes)` —— 中国用户的 .md 常含 GBK 字节

### 4.4 错误传播

- 服务层抛业务异常（`ExportException` / `FileImportException` 等），不抛 raw `Exception`
- UI 层通过 [export_service.dart:261-348](file:///d:/Projects/Active/math2/flutter_app/lib/domain/services/export_service.dart#L261-348) `classifyError` 映射到 `ExportFailure` 枚举
- **禁止把 `detail`（含 source/offset/stack）直接显示给用户** —— 当前 [editor_screen.dart:230-253](file:///d:/Projects/Active/math2/flutter_app/lib/presentation/screens/editor_screen.dart#L230-253) 违反此规则，待 P1 修复

---

## 5. Git 提交规范

详见 [docs/GIT_WORKFLOW.md](docs/engineering/GIT-WORKFLOW.md)。要点：

### 5.0 AI / Human 提交分工（核心规则）

| 行为 | AI | Human Owner |
|------|----|-------------|
| 创建独立 branch | ✅ 必须 | ✅ |
| 创建 commit | ✅ 可以 | ✅ |
| Commit message 含任务范围 | ✅ 必须 | — |
| 创建 PR | ✅ 必须 | ✅ |
| 直接 push 到 `main` | ❌ 禁止 | ✅ |
| Merge PR | ❌ 禁止 | ✅ 专属权限 |
| 架构决策类文件 commit | ❌ 禁止（除非明确授权） | ✅ 专属权限 |

详见 [§6.4](#64-ai--human-提交分工)。

### 5.1 Commit Message 格式（Conventional Commits）

```
<type>(<scope>): <subject>

<body>

<footer>
```

**type**：`feat` / `fix` / `refactor` / `docs` / `chore` / `test` / `perf` / `style` / `ci` / `build`

**scope**：模块名（如 `parser` / `exporter` / `ui` / `ci` / `docs`）

**AI commit 强制要求**：body 必须包含任务范围，格式：
```
Task scope: <ROADMAP phase.task 或 issue 编号>
```

**示例（AI commit）**：
```
feat(parser): 支持 Markdown 行内代码与链接语法

补齐 _parseBoldAndItalic 中缺失的 `code` 与 [text](url) 解析分支

Task scope: ROADMAP 1.5
Closes #12
```

**示例（Human commit，架构决策）**：
```
docs(adr): 新增 ADR-0007 StorageMigration 设计

按重构方案 R1 要求，补充存储迁移的幂等性、备份、回滚策略。
```

### 5.2 Branch 策略

- `main`：受保护，只接受 PR 合入
- `develop`：日常集成分支（Phase 1 启用）
- `feat/<scope>-<short-desc>`：功能分支，如 `feat/parser-inline-code`
- `fix/<scope>-<short-desc>`：bug 修复分支
- `chore/<short-desc>`：工程化任务
- `docs/<short-desc>`：文档变更

### 5.3 PR 检查清单

PR 描述必须包含：

- [ ] 关联 issue 编号
- [ ] 改动说明（what + why）
- [ ] 测试方式（手动 / 自动）
- [ ] 是否影响公共 API
- [ ] 是否更新文档
- [ ] 自测：`flutter analyze --no-fatal-infos --fatal-warnings` 无 error / 无 warning（与 CI [Analyze 步骤](file:///d:/Projects/Active/math2/.github/workflows/ci.yml) 一致；裸 `flutter analyze` 只把 warning 当 info 显示，本地可能漏检）
- [ ] 自测：`flutter test` 全部通过
- [ ] 自测：`flutter build apk --debug` 成功（Android 构建）
- [ ] 自测：`flutter build web` 成功
- [ ] 修改 `android/` 或 `pubspec.yaml` 后：本地验证 compileSdk / AGP / Gradle 版本兼容性

---

## 6. 禁止事项（Hard Rules）

### 6.1 业务代码禁区

1. ❌ **禁止** 在 `core/` 内 import `presentation/` 或 `domain/`
2. ❌ **禁止** 在多个文件定义同名 Provider
3. ❌ **禁止** 在 UI 层直接展示异常 `detail` / `stack`
4. ❌ **禁止** 使用 `print()`，必须用 `debugPrint()`
5. ❌ **禁止** 在 `main()` 中写业务逻辑，只允许 runApp + 初始化
6. ❌ **禁止** 在 `setState` 之外的同步代码里修改 Provider state
7. ❌ **禁止** 引入新的全局静态状态（已有 `MermaidService._cache` 等是历史遗留，重构时清理）

### 6.2 工程禁区

1. ❌ **禁止** 提交 `build/` 目录
2. ❌ **禁止** 提交 `.dart_tool/` 目录
3. ❌ **禁止** 提交 `pubspec.lock`（如果是 App 项目；库项目需要提交）
4. ❌ **禁止** 提交含密钥的文件（`.env` / `google-services.json` 等）
5. ❌ **禁止** 跳过 CI 直接 push `main`
6. ❌ **禁止** 提交一次性文件（临时调试文件、测试产物等），使用后必须及时清理
7. ❌ **禁止** 在 PowerShell 中直接调用 `flutter.bat`（stdout 缓冲死锁，用 Git Bash 代替）
8. ❌ **禁止** 升级 AGP / Gradle / Kotlin 版本而不验证 inappwebview 全家桶编译通过
9. ❌ **禁止** 移除 `pubspec.yaml` 中 `flutter_inappwebview_*` 的 `dependency_overrides` 稳定版锁定
10. ❌ **禁止** 用 `sed` / `afterEvaluate` / 多 `subprojects` 块修补 compileSdk（用 `gradle.afterProject`）
11. ❌ **禁止** 直接修改 pub cache 中插件的源文件（污染全局，用 `dependency_overrides` 替代）
12. ❌ **禁止** 在项目根目录遗留一次性文件（CI 日志、调试输出、临时压缩包）—— 用完即删，不入库

### 6.3 AI 协作禁区

1. ❌ **禁止凭空设计**：所有架构决策必须有代码依据，并落地为 ADR
2. ❌ **禁止跨阶段实现**：当前阶段为 Phase 0 工程化，禁止在未完成 P0 修复前实现新业务功能
3. ❌ **禁止大规模重构与功能改动混在同一 PR**：重构 PR 必须 0 业务行为变化
4. ❌ **禁止删除测试以通过 CI**：测试失败必须修代码，不修测试（除非测试本身有 bug）

### 6.4 AI / Human 提交分工

| 行为 | AI | Human Owner |
|------|----|-------------|
| 创建 branch | ✅ 必须（独立分支） | ✅ |
| 创建 commit | ✅ 可以 | ✅ |
| Commit 必须包含任务范围 | ✅ 必须 | — |
| 创建 PR | ✅ 必须 | ✅ |
| 直接 push 到 `main` | ❌ 禁止 | ✅ |
| Merge PR | ❌ 禁止 | ✅ 专属权限 |
| 架构决策类文件 commit | ❌ 禁止 | ✅ 专属权限 |

**架构决策类文件**指：
- `docs/decisions/ADR/*.md`（架构决策记录）
- `AGENTS.md`（协作规范本身）
- `docs/architecture/ARCHITECTURE.md` / `docs/ROADMAP.md` / `docs/archive/REFACTOR_DESIGN.md` 等架构文档
- `docs/archive/audits/CRITICAL-REVIEW.md`（架构评审）

**例外**：当 Human Owner 明确授权时（如在任务说明里写明"请你同时更新 ADR-XXXX"），AI 可以 commit 架构决策类文件，但仍必须走 PR 流程。

### 6.5 当前阶段特别禁止

在 Phase 2 编辑模型阶段，额外禁止：

1. ❌ 修改 UI 行为（Phase 1-2 仍属 UI Prototype Freeze 期，UI 在 Phase 3 重写）
2. ❌ 新增 Phase 3 才有的功能（主题切换 / TOC / 图片管理 / 焦点模式等）—— 详见 [ROADMAP Phase 3](file:///d:/Projects/Active/math2/docs/ROADMAP.md)
3. ❌ 在 BlockEditor 抽象稳定前（Phase 2.1）实现 2.2~2.7 的细节
4. ❌ 跨阶段引入 SQLite / FileIndex 等派生缓存（[ADR-0003](file:///d:/Projects/Active/math2/docs/decisions/ADR/0003-storage-single-source-md-files.md) §边界约束 5）—— 留到 Phase 2 性能优化

---

## 7. 文档体系

```
.agent/                        AI 工程治理层
├── REPO_POLICY.md             ★ 安全层总纲：四层根因模型、文件索引、事故登记
├── ENVIRONMENT.md             ★ 仓库物理边界事实（repo root / flutter_app 是子目录）
├── GIT_RULES.md               ★ git 红黄绿三级禁令 + 例外授权 + 损坏应急 SOP
├── COMMAND_SAFETY.md          ★ 危险命令清单 + 三条强制前置 + 变量展开陷阱
├── AI_POLICY.md               Agent 身份、权限、行为协议
├── GIT_POLICY.md              分支/PR/merge 权限边界
├── tools/
│   └── guard.sh               机器强制层：assert_safe_target / nested / doctor
├── context/
│   └── loading-rules.md       分级上下文加载规则
├── templates/
│   └── task-contract.md       任务契约模板
└── state/                     运行时状态（.gitignore 忽略，不入库）

docs/                        四层信息架构（人类入口 / 工程真相 / 历史档案 / 机器资产）
├── README.md                人类导航（按阅读目的：新人 / 改代码 / 决策 / 验证 / 历史）
├── INDEX.md                 全量索引
├── ROADMAP.md               路线图（Phase 0-4）
├── product/                 产品真相（PRODUCT / UX-GUIDE / TYPORA-GAP / CAPABILITY-STATUS）
├── architecture/            架构真相（ARCHITECTURE / EDITOR-MODEL / EXPORT-MODEL / UI-*）
├── engineering/             工程真相（BASELINE / GATE-REPORT / RULES / WORKFLOW / VERIFICATION-POLICY）
├── decisions/               决策真相（INDEX 状态表 + ADR/ 29 篇）
│   └── ADR/                 架构决策记录（每条决策一份）
├── contracts/               任务契约
├── design/                  设计文档
├── releases/                11 篇 release notes
├── regression/              回归用例包（BUG-001~003）
├── evidence/                证据索引（capability / visual / consumer）
└── archive/                 历史档案（audits / runs / spikes / investigations / old-designs / governance）
```

### ADR 编写规则

- 文件名：`NNNN-<kebab-case-title>.md`，NNNN 从 0001 递增，不复用
- 状态：`Proposed` → `Accepted` → `Superseded by ADR-NNNN` / `Deprecated`
- 内容必须包含：背景、决策、动机、后果、替代方案

---

## 8. CI 与质量门禁

详见 [.github/workflows/ci.yml](file:///d:/Projects/Active/math2/.github/workflows/ci.yml)。

**PR 合并必须满足**：

1. `flutter pub get` 成功
2. `flutter analyze --no-fatal-infos --fatal-warnings` 无 error / 无 warning
3. `flutter test` 全部通过
4. `flutter build` 成功（apk + web 两平台）

**当前状态**：全部 4 项门禁通过。

---

## 9. AI 协作工作流（TRAE / Claude / Cursor 等）

### 9.1 接到任务时的标准流程

1. **先读文档**：本文件 + 相关 ADR + ROADMAP 当前 Phase
2. **再读代码**：相关模块的实际实现，不依赖文档描述
3. **判断阶段**：当前任务是否在允许的阶段范围内
4. **写 todo**：复杂任务（>3 步）必须用 TodoWrite
5. **最小改动**：能改一行不改两行
6. **写测试**：新功能必须有测试；bug 修复必须有回归测试
7. **写文档**：架构决策必须落 ADR
8. **自检**：参照本文档禁止事项逐条确认

### 9.2 编码前必须回答的四个问题

AI Agent 在开始编码前，必须填写 [Task Contract](file:///d:/Projects/Active/math2/.agent/templates/task-contract.md)，明确回答：

1. **What changes?** — 修改哪些文件？为什么？
2. **How to verify?** — 测试在哪里？如何证明正确？
3. **What feedback signals exist?** — 成功指标是什么？失败指标是什么？
4. **What is done?** — 什么条件满足才算完成？

复杂任务（Risk Medium+ 或涉及架构变更）的 Task Contract 须提交 Human Owner 审批后再开始实现。

### 9.3 不确定时的升级路径

- 业务范围不清 → 看 ROADMAP / 问用户
- 架构选型不清 → 看 ADR / 提新 ADR
- API 兼容性疑问 → 看相关模块 dartdoc
- 测试策略疑问 → 看 CODING_RULES.md 第 6 章

### 9.4 PR 提交前的自检清单

- [ ] 读了 AGENTS.md 相关章节
- [ ] 没有违反任何 Hard Rules
- [ ] 改动范围与 PR 描述一致
- [ ] 没有夹带未在 PR 描述中说明的改动
- [ ] 测试覆盖完整
- [ ] 文档已同步

### 9.5 ADI 诊断工作流（引用 ADR-0024 §1.4）

AI Agent 调试 Tafcm 时，若使用 ADI（Agent Diagnostic Interface），**MUST** 遵守 [ADR-0024 §1.4 Agent Interaction Contract](file:///d:/Projects/Active/math2/docs/decisions/ADR/0024-agent-diagnostic-interface.md)：

1. **Query first** — 先 `adi latest-error --json` 获取 Observation，不凭空假设
2. **Inspect before edit** — 改代码前先 `adi trace show <id>` 理解因果链
3. **Replay before modify** — 改代码前先 `adi replay <id>` 确认能复现（不能复现的 bug 不应修）
4. **Validate after modify** — 改完代码后 `adi validate --after-fix` 验证闭环
5. **Never trust candidate_causes as truth** — `candidate_causes` 是假设非结论，修复决策需 Agent 推理
6. **Respect invariant report** — `invariant_report.violated` 非空 = 状态损坏（真 bug）；全通过 = 渲染降级或既定行为（ADR-0022）

ADI 复用 Phase 3.7 已建成的采集能力，不重新采集证据。CLI 入口：`dart run tools/adi/adi.dart <command>`。详见 [ADR-0024](file:///d:/Projects/Active/math2/docs/decisions/ADR/0024-agent-diagnostic-interface.md) + [ADI Design Document](file:///d:/Projects/Active/math2/docs/design/adi-design-v1.md)。

---

## 10. 当前阻塞项与例外说明

以下是已知问题，已记入 [CRITICAL_REVIEW.md](docs/archive/audits/CRITICAL-REVIEW.md)。

**Phase 1 已修复项**（2026-07-19，PR #23 合并后正式关闭）：

| 问题 | 修复 commit / PR | 证据 |
|------|----------------|------|
| Provider 重复定义 | `ec76f06`（1.1） | [test/architecture/provider_uniqueness_test.dart](file:///d:/Projects/Active/math2/flutter_app/test/architecture/provider_uniqueness_test.dart) 守门 |
| 三套存储并存 | `b43e5c1`（1.2） | [ADR-0003](file:///d:/Projects/Active/math2/docs/decisions/ADR/0003-storage-single-source-md-files.md) Implemented |
| 解析器缺 7 类元素 | `da4ab00`（1.5） | [test/parser/edge_case_test.dart](file:///d:/Projects/Active/math2/flutter_app/test/parser/edge_case_test.dart) |
| DocumentListScreen 死代码 | `b36d930`（1.3） | 路由已合并到 `/files` |
| 错误 detail 透传 UI | `f6a73af`（1.7） | [test/error/message_friendly_test.dart](file:///d:/Projects/Active/math2/flutter_app/test/error/message_friendly_test.dart) |

**仍存在项**（按 Phase 修复）：

| 问题 | 修复 Phase | 跟踪 |
|------|----------|------|
| 编辑/预览分离模式 | Phase 3 UI Implementation | [ROADMAP 3.1](file:///d:/Projects/Active/math2/docs/ROADMAP.md) |
| 静态状态污染测试 | Phase 2 | [CRITICAL_REVIEW §8.5](docs/archive/audits/CRITICAL-REVIEW.md) |

新增代码不得延续以上问题，必须按目标架构编写。

---

## 11. CI 高频失败模式与修复手册

> 记录 2026-07 以来反复出现的 CI 失败模式及已验证修复方法。
> 每条模式包含：症状（CI log 关键行）、根因、修复、preflight 自检命令。

### 11.1 `unused_import` → Analyze 失败

**症状**：CI Analyze 步骤报 `warning - Unused import: 'dart:typed_data'` → `--fatal-warnings` 视为失败。

**根因**：删代码/字段（如移除 `Uint8List` 用法、移除 `ExportCompletedState.bytes` 字段）后未同步删 import。

**修复**：删相关 `import 'dart:typed_data';`（或对应无用 import）。

**preflight 自检**：
```bash
cd flutter_app && flutter analyze --no-fatal-infos --fatal-warnings
# 裸 flutter analyze 只把 warning 当 info 显示 → 本地可能漏检
```
**教训出处**：PR #78 Slice 7 首跑 CI（`449ee4b` 删 `_shareBytes` 后未删 `dart:typed_data`）；PR #78 评审修复（移除 `ExportCompletedState.bytes` 后未删 `dart:typed_data`）。

### 11.3 SDK API 误用 → 反复 push 多次才能闭环

**症状**：CI 报 `Undefined getter / Undefined name / Undefined class` 等分析错误，多次 commit 反复试错才能收敛。

**根因**：直接根据训练记忆/经验推断 Flutter SDK API 签名，未先 Read 真实源码；或在 widget test binding 下 API 行为与本机 SDK 文档不一致但未对照实测。

**修复模板**：
1. 修改前先用 `grep -n "<symbol>" <flutter SDK>/packages/<pkg>/lib/src/<file>.dart` 定位真实定义
2. Read 该位置 ±20 行确认签名（参数类型、返回类型、deprecated 状态）
3. 跨版本不稳定的 API（如 `SemanticsFlags.isToggled` 在不同 Flutter 版本可能返回 `bool?` / `Tristate` / `int`）：用 `expect(actual.toString(), ...)` 跨版本兼容写法，或绕开该断言由组件代码注释保证
4. **测试代码里 `tester.ensureSemantics()` 是常见重复创建陷阱**——`testWidgets` 默认 `semanticsEnabled=true`（见 SDK `widget_tester.dart:153`），test runner 已自动创建并 dispose 一个 handle；测试体里**不要再 `ensureSemantics()`**

**preflight 自检**：
```bash
cd flutter_app && flutter analyze --no-fatal-infos --fatal-warnings <file>
cd flutter_app && flutter test test/<dir>/<file>_test.dart
```

**强制项**：
- **任何 commit 前必须本地跑 `flutter analyze` + `flutter test` 对应文件**——CI 不是唯一守门，本机是更早的一道闸
- **L1 干扰（Defender 实时删工作树）**只影响全量 `flutter` 套件，单文件 `flutter test <file>` 可正常跑出
- **pre-push hook 仍需 `SKIP_PREFLIGHT=1` 跳过**——它跑全量 preflight，单文件验证不受影响

**教训出处**：PR #117 CI 修复 5 个 commit 反复试错（`ab91c32` / `b28db34` / `e41d03a` / `7e85aa1` / `7db6f71`）。toggle 断言连续踩 3 次 SDK API 误用坑；SemanticsHandle 双创建直到核 `widget_tester.dart:153` 才定位根因。教训：**先 Read 真实源码再下笔**——训练记忆会在 SDK 跨版本时作恶。

### 11.2 架构守门 `TC-ARCH-1/2`（presentation 层直接文件 I/O）

**症状**：CI Test 步骤 `test/architecture/file_access_test.dart` 失败：
- `TC-ARCH-1`：`lib/presentation/` 下禁止 `File()` / `Directory()` 调用
- `TC-ARCH-2`：`writeAsString` / `writeAsBytes` 仅 allowlist 文件可调用

**根因**：在 presentation 层（`editor_page.dart`）直接 `File(path).writeAsBytes()` 写临时文件给 share sheet。

**修复**：把 I/O 抽到 domain 层 allowlist 内：
- `ExportService.writeBytesToTempFile(bytes, format, fileName:)` → 返回 path
- presentation 只拿 path 调 `Share.shareXFiles([XFile(path)])`

**preflight 自检**：
```bash
cd flutter_app && flutter test test/architecture/file_access_test.dart
```
**allowlist 文件**：`file_repository.dart` / `file_service.dart` / `storage_migration.dart` / `document_service.dart` / `export_service.dart`（export 域也可写临时文件）。

**教训出处**：PR #78 Slice 7 首跑 CI（`65e2b67` 直接在 `editor_page.dart` 写临时文件）。

### 11.3 文件超 400 行 `TC-ARCH-7`

**症状**：CI Test 步骤 `test/architecture/file_size_test.dart` 失败。

**根因**：新增/修改 `.dart` 文件超过 400 行（AGENTS.md §1.2 单一职责）。

**修复**：
- lib/ 文件：加入 `knownOffenders` 豁免列表（仅限已存在且合理密集的模块，如 parser/exporter/cache）
- test/ 文件：强制拆分（测试文件无豁免），1 个文件含数据层+widget 层 → 拆为 `_test.dart` + `_widget_test.dart`

**preflight 自检**：
```bash
# 先看行数
wc -l flutter_app/lib/**/*.dart flutter_app/test/**/*.dart | sort -rn | head -20
# 超 400 行的 test 文件必须拆
cd flutter_app && flutter test test/architecture/file_size_test.dart
```
**教训出处**：PR #78 Slice 7 首跑 CI（export_progress_test.dart 446 行 → 拆为 225+231 行两文件）；formula_pdf_renderer.dart 409 行 → 加入 knownOffenders。

### 11.4 main-merge 交叉 PR 特性冲突（`undefined_*` 大爆发）

**症状**：CI Analyze 报 **14+ 个 `undefined_identifier` / `undefined_getter` / `undefined_class` / `type_argument_not_matching_bounds`**，全落在 **PR 作者未修改的文件区域**（如 `editor_app_bar` / `editor_shell` / `editor_page` 中的 `onOpenFileTree` / `themeMode` / `ImagePickAndImport` / `ConsumerStatefulWidget` 等字段）。

**根因**：主分支已合并其它 PR（3.4.2 文件树 / 3.4.3 主题 / 3.4.9 图片），当前 PR 分支基于更早的 base（pre-merge）。owner 或用 GitHub Web UI "Merge branch 'main'" 后，3-way merge 带入了新特性代码的**字段引用**但未合并**字段声明与 import**。

**修复**：
1. **不要基于旧 base 的 commit 直接修**——旧 base 缺失主分支新引入的类/Provider/字段定义。
2. 基于 `origin/main` 重建 self-consistent commit tree：
   - fetch origin/main 全部实际可获取文件（跳过 missing blob，见 §12）
   - 在新 base 内容上叠加本 PR 改动
   - 提交前本地跑同款 `flutter analyze` 命令验证
3. 若 main 自身有 force-push 残留 missing blob（`git fsck` 报），写占位文件替换（见 §12.1），commit parent 尽量用 self-consistent base。

**教训出处**：PR #77 `4dbe0c7` Merge main（5 处 analyzer 错，全在我未改区域）；PR #78 `2212aee` Merge main（14 处）。

### 11.5 Widget 测试未注入 `EditorTokens` → Test 失败

**症状**：CI Test 报 `EditorTokens 未注入当前 ThemeData`（`FlutterError`）。

**根因**：Phase 3.4.3（PR #71）后 `CodeBlock`/`TableBlock` 等在 build 时调用 `EditorTokens.of(context)`。Widget 测试用裸 `MaterialApp` 或 `const MaterialApp(...)` 未注入 `AppTheme.lightTheme`。

**修复**：
```dart
MaterialApp(
  theme: AppTheme.lightTheme,  // 不可 const
  home: ...,
)
```

**preflight 自检**：新 widget 测试涉及 `EditorPage`/`EditorShell`/`TocPanel`/种子文档块 → 检查是否已挂 `theme: AppTheme.lightTheme`。

**教训出处**：PR #77 `c970c08` 修复 commit 补两个测试的 `theme: AppTheme.lightTheme`。

### 11.6 `ref.listen` 不在初始值触发 → SnackBar/Overlay 不出现

**症状**：CI Test 找不到 `SnackBar` / `LinearProgressIndicator`（`expect(find.byType(SnackBar), findsOneWidget)` 失败，实际 findsNothing）。

**根因**：Riverpod `ref.listen(callback)` 只在 provider state **变化**时调用，**首次注册时不触发**。测试代码在 `pumpWidget` **之前**改了 state → `pumpWidget` 后 listener 才注册 → 错过触发。

**修复**：用 `addPostFrameCallback` 把 state mutation 调度到首帧之后：
```dart
await tester.pumpWidget(UncontrolledProviderScope(
  container: container,
  child: Consumer(builder: (context, ref, _) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      container.read(exportProgressProvider.notifier).start(format);
    });
    return const ExportProgressOverlay(child: Text('anchor'));
  }),
));
await tester.pump();  // Frame 1：widget 挂载 + listener 注册
await tester.pump();  // Frame 2：postFrame 执行 → listener 触发
```

**教训出处**：PR #78 Slice 7 ExportProgressOverlay 测试首次失败 4 个。

### 11.7 `document_list_screen.dart` 占位缺失 AppBar → router_integration_test 失败

**症状**：CI Test 报 `test/router_integration_test.dart: DocumentListScreen 可构建，AppBar 显示"Tafcm"` 失败。

**根因**：因 main 仓库缺失真实 `document_list_screen.dart` blob（§12.1），写了占位但占位不含 `AppBar(title: Text('Tafcm'))`。

**修复**：占位必须含 `Scaffold(appBar: AppBar(title: const Text('Tafcm')))`。

**教训出处**：PR #78 `6f88844` → CI 30227895402 Test 失败 1 个。

### 11.8 全功能落地但一键未接线 → 导出按钮/Overlay 不渲染

**症状**：代码评审发现 widget 树中从未传入 `onExportTo` 参数、从未 wrap `ExportProgressOverlay`、EditorPage 无 `_handleExport` 方法。PopupMenuButton 因 `onExportTo == null` 永不渲染。

**根因**：domain/provider 层实现完整，但 presentation 层 3 个文件的集成代码（import、字段声明、参数传递、回调注入）遗漏——PR 头 tree 重建时未能把 presentation 编辑同步进去。

**修复**：
1. `editor_shell.dart`：加 `final ValueChanged<ExportFormat>? onExportTo` 字段 → 传入 `EditorAppBar(onExportTo: widget.onExportTo)`
2. `editor_page.dart`：加 imports（`share_plus` / `export_progress_provider` / `export_service` / `app_theme`）→ 新增 `_handleExport(ExportFormat)` 方法 → `ExportProgressOverlay` wrap `EditorScope` → `onExportTo: _handleExport` 注入
3. 同步新 feature 的 "3 件套" 检查清单：
   - ✅ domain/ 类型 + provider 定义
   - ✅ presentation/ 字段 + 参数声明
   - ✅ presentation/ 构造注入 + 回调接线

**教训出处**：PR #78 评审反馈（问题 1，严重）。

---

## 12. Git 版本管理硬伤与绕过（环境特异）

> **⚠️ 2026-07-30 状态变更：§12.2 的 unified workaround 已退役，不再是强制流程。**
>
> **权威规则以 [`.agent/GIT_RULES.md`](.agent/GIT_RULES.md) 为准**（Repository Safety Layer）。
> 本章仅作历史归档与应急回退手册保留。
>
> **变更原因**：§12.2 的根因是 L1 环境层——Windows 资源管理器 git 壳扩展 +
> SearchIndexer 持锁 `.git`。2026-07-30 用户关闭壳扩展后，原生 git 压力测试
> （commit ×5 / add / checkout / reset --soft）**全部通过，平均 420ms**，
> `git fsck` 零输出。L1 消失，绕过术失去存在理由。
>
> **为什么必须退役而非"留着以防万一"**：§12.2 全套操作（`commit-tree`、
> `update-ref`、`printf > .git/refs/heads/...`）都是**绕开 git 安全护栏直接改写
> 底层存储**。每执行一次就多一次写坏 ref/index 的概率。2026-07-26 两次仓库损坏
> （对象 DB 缺 blob、`refs/heads` 子目录消失）正是这套流程的副作用——
> **它本是为了应对损坏，结果自己成了损坏的主要来源。**
>
> **现行规则**：日常一律用原生 `git add` + `git commit` + `git push`。
> 仅当原生命令确实因文件锁失败时，才按 `.agent/GIT_RULES.md` 的例外流程
> （用户授权 + 备份 + 事后 fsck）临时启用本章方案。

### 12.1 main 仓库 force-push 残留 missing blob

**症状**：
```bash
$ git fsck --no-progress
missing blob 3298c833beccf2a6f211f3dc65b2a8ad70e89723  # editor_tokens.dart
missing blob 23a03e1918205d2b6bb8fb4dc311813564378b66  # document_list_screen.dart

$ git fetch origin 3298c833beccf2a6f211f3dc65b2a8ad70e89723
fatal: bad object ...
error: github.com:Thy985/fixmath.git did not send all necessary objects
```

**影响**：
- `git checkout origin/main` / `git reset --hard origin/main` 失败（无法 resolve blob）
- `flutter analyze` 报 `undefined_*` 错（这 2 个文件的 import 链断裂）
- `git push` 会因 commit tree 引用 missing blob 而拒收

**绕过**：
- 写最小占位文件替换（满足 import 解析 + test 守门）：
  - `editor_tokens.dart`：完整 PR #71 字段集（9 主题字段 + 3 主题实例 + `of(context)`）——仅 1-2 字段不够，`code_block`/`mermaid_block` 等引用完整字段集
  - `document_list_screen.dart`：`Scaffold + AppBar(title: Text('Tafcm'))` ——满足 `router_integration_test.dart:55`
- **PR commit parent 不要用 main (02afb030)**——push 时 GitHub 因 parent tree 引用 missing blob 拒收
- 用 self-consistent base（如 PR #78 的 `7c9abc4`）+ 写入 main 全部改动

**诊断**：
```bash
git fsck --no-progress | head -10
for sha in $(git ls-tree -r <commit> | awk '{print $3}' | sort -u); do
  git cat-file -e "$sha" 2>/dev/null || echo "MISS $sha"
done
```

**教训出处**：PR #78 `2212aee` / `02afb030` main 均引用这 2 个 missing blob。

### 12.2 Unified Git Workaround（⚠️ 已退役 — 仅应急回退）

> **状态：RETIRED（2026-07-30）**。日常**禁止**使用；启用需满足
> `.agent/GIT_RULES.md` 的例外条件（原生 git 实测失败 + 用户授权 + 备份 + 事后 `git fsck`）。
> 步骤 7 的 `printf > .git/refs/...` 属**红线操作**，即便应急也须逐条确认。

历史背景：本环境曾出现 `git commit` 不可用（COMMIT_EDITMSG 锁）+ 本地 ref 存储失稳
（子路径分支自动丢失），当时的绕过流程如下（保留供应急参考）：

```bash
# 0. 准备消息文件（注意：commit-tree 传消息用 < file 喂 stdin，勿用 -F）
echo "feat(scope): subject" > /tmp/msg.txt
echo "" >> /tmp/msg.txt
echo "body lines..." >> /tmp/msg.txt
echo "" >> /tmp/msg.txt
echo "Task scope: ROADMAP X.Y" >> /tmp/msg.txt

# 1. 用临时索引（GIT_INDEX_FILE 放系统 temp 目录，避开 .git/ 沙箱文件句柄冲突）
export GIT_INDEX_FILE="C:/Users/lenovo/AppData/Local/Temp/build.index"
rm -f "$GIT_INDEX_FILE"

# 2. read-tree 把 base commit（parent）的 tree 读入索引
PARENT=$(git rev-parse feat/phase3.4-xxx)  # 或 origin/main
git read-tree $PARENT

# 3. 逐文件 stage（hash-object + update-index --add --cacheinfo）
for f in path/to/file1.dart path/to/file2.dart; do
  sha=$(git hash-object -w "$f")
  git update-index --add --cacheinfo 100644,$sha,"$f"
done

# 4. write-tree → 构建 TREE 对象
TREE=$(git write-tree)

# 5. commit-tree 创建 commit（stdin 重定向绕开 -F 无法打开消息文件的沙箱问题）
NEWSHA=$(git commit-tree $TREE -p $PARENT < /tmp/msg.txt)

# 6. 显式 SHA push（不用 HEAD 解析，绕开 ref 存储失稳）
git push origin $NEWSHA:refs/heads/feat/phase3.4-xxx

# 7. 同步本地 ref（绕开 ref 子目录失稳）
printf "$NEWSHA\n" > .git/refs/heads/feat/phase3.4-xxx
# remote-tracking ref（路径可能需逐级 mkdir）
mkdir -p .git/refs/remotes/origin/feat
printf "$NEWSHA\n" > .git/refs/remotes/origin/feat/phase3.4-xxx
```

**注意事项**：
- `$NEWSHA` 必须是**完整 40 字符**，7 字符缩写会导致 `git show-ref` 报 "bad ref"
- `commit-tree` 传消息**勿用 `-F <file>`**（本环境 git 打不开消息文件），用 `< file` 喂 stdin
- 工作树路径用 Windows 风格 `C:/Users/...`，不要用 `/c/Users/...`（MSYS 路径在 `GIT_INDEX_FILE` 中不工作）
- push 后立刻验证：
  ```bash
  git ls-remote origin feat/phase3.4-xxx  # 远端 ref 确认
  git show-ref | grep feat/phase3.4-xxx    # 本地 ref 确认
  ```

### 12.3 Force-push 后 CI 触发异常

**症状**：force-push 后 `gh run list --branch <branch>` 看到 CI 触发但某些 job（Test/Build）在 "Setup Flutter" 阶段 `canceled`。

**根因**：GitHub Actions runner Flutter SDK 缓存下载偶发网络 rate limit（`Received ... of ... (xx.x%)` 后 `##[error]The operation was canceled`）。

**修复**：`gh run rerun <run_id> --failed` 重跑失败 job；若仍失败等 2-3 分钟后手动 rerun。

**教训出处**：PR #77 / #78 多次 force-push 后 CI flake。

### 12.4 PR mergeable 状态权威性

**规则**：PR mergeable 状态以 `gh pr view <N> --json mergeable` 返回值为准。首次 force-push 后可能短暂显示 `CONFLICTING`，GitHub 后台重新计算后自行更新为 `MERGEABLE`。

**教训出处**：PR #78 force-push `056be28` 后短暂 `CONFLICTING`，owner merge main 后自动变为 `MERGEABLE`。

---

## 12. Bug Fix Protocol（强制）

> **来源**：Claude Code 洞察报告（2026-08-17）—— 用户在 10+ 个会话中以 "fix bug" 发起请求却未提供任何细节，导致整段会话时间浪费在 onboarding 和证据收集上，从未达成任何诊断或修复。
>
> **本章节优先级高于所有其他条款**：AI Agent 必须在收到 bug 报告时先执行 §12.1，否则视为违反协议。

### 12.1 Before Investigation — 强制信息收集

收到 "fix bug" / "修 bug" / "解决 XX 问题" 类请求时，**MUST** 先确认拥有以下至少一项：

| 必需信息 | 示例 |
|---------|------|
| (1) 错误输出 / Stack Trace | CI log 关键行、运行时异常堆栈 |
| (2) Failing Test 或复现步骤 | `flutter test test/parser/...` 失败、具体操作步骤 |
| (3) 受影响文件或组件 | `lib/core/parser/markdown_parser.dart`、`EditorPage` |

若以上均缺失，**必须询问用户**，禁止自行猜测或开始调查：

```
我需要以下信息才能开始调查：
1. [ ] 错误输出 / stack trace（CI log 关键行、运行时异常）
2. [ ] 复现步骤或 failing test
3. [ ] 受影响文件或组件（如有）

请补充任意一项，我立刻开始诊断。
```

### 12.2 Debugging Protocol（拿到信息后）

```
Reproduce → Collect Evidence → Find Root Cause → Fix → Regression Protection
```

1. **Reproduce**：先跑 failing test 或手动复现，确认问题存在
2. **Collect Evidence**：读相关代码 + 读相关 ADR + 查 CI log + 检查 git blame
3. **Find Root Cause**：写出原因（X）+ 证据（Y）+ 方案（Z），禁止跳步
4. **Fix**：最小改动原则，一个 PR 只修一个问题
5. **Regression Protection**：补测试或更新 TEST_SKIP_REGISTRY

### 12.3 例外情况

以下情况可跳过 §12.1 信息收集直接行动：

| 例外类型 | 例 | 必要条件 |
|---------|----|---------|
| Typo / 拼写修复 | 一行错别字 / 一个变量名拼错 | 改动 ≤ 1 个文件 / ≤ 5 行 |
| 纯文档措辞调整 | README / 注释错字 | 不影响契约 / 不影响架构表述 |
| 已显式授权的紧急修复 | hotfix / 现网事故兜底 | 用户在当前对话中显式说出 "skip bug protocol" 并说明紧急理由 |

出现上述例外时，须在最终回复里声明已跳过 §12.1 并写明对应例外。

---

## 13. Testing

> **来源**：Claude Code 洞察报告 —— 长会话被 Classifier 写入超时、Flutter E2E 测试超时打断，导致闭环未完成。

### 13.1 验证基线

所有工作按以下基准验证：

| 命令 | 用途 | 备注 |
|------|------|------|
| `flutter analyze --no-fatal-infos --fatal-warnings` | Analyze 门禁 | 必须用此精确命令，裸 `flutter analyze` 不把 warning 当 error |
| `flutter test` | 全量 unit/widget test | 185 个 *_test.dart / ~1700+ 用例（2026-08-26 实测），全量需 3-5 min+ |
| `flutter test test/<dir>/<file>_test.dart` | 单文件测试 | 短耗时，适合迭代验证 |
| `ffx test` | ffx-cli 测试 | 170+ pytest 用例（与 §14.1 树注一致），改 CLI 后必跑 |
| `ffx adi doctor` | ADI 自检 | 跑 ADI 前必做 |

### 13.2 已知超时风险

- **Classifier 写入超时**：`adi validate` / `adi aggregate` 可能卡在写入 step，等待 >120s → 中断重试
- **Flutter E2E（integration_test）**：单文件约 50s，全轮约 18min；Gradle 偶发网络抖动（`Connection reset`）→ 重跑即过
- **Golden test diff**：见 `flutter_app/test/golden/failures/` 目录，已登记 skip

### 13.3 长测试运行策略

> 会话超时风险高时，使用后台运行 + Monitor 模式：

```bash
# 后台跑全量 test，完成后通知
cd flutter_app && flutter test 2>&1 | tee /tmp/flutter_test.log
# 或用 Monitor 工具持续观察
```

---

## 14. Project Architecture

### 14.1 整体结构

> **同步时间**：2026-08-25（PR-5 `docs/sync-top-level-inventory-2026-08-25`）
> **依据**：`git ls-tree --name-only HEAD` 实测（2026-08-25 治理轮 PR #167-#172 执行结果为准；原 `REPO_AUDIT_2026-08-25.md` v4 报告未入库，本节以实测与治理轮执行为权威）
> **tracked 顶层**（17 个）：`.agent` `.arts` `.githooks` `.github` `AGENTS.md` `LICENSE` `README.md` `contracts` `design-system` `docs` `flutter_app` `formulafix-redesign.design` `skills` `tests` `tools` + 2 git 元数据文件 `.gitattributes` `.gitignore`
> **ignored 顶层**（10 个，gitignore 拦截）：`.adi` `.claude/hooks.log` `.codeartsdoer` `.debug` `.ffx` `.openwiki` `.wt` `.workbuddy` `flutter_app/build/` `flutter_app/.dart_tool/` + 等等
> **临时 untracked**（通常应忽略）：`.atomcode/memory.md`（preflight Windows fix 备忘，待后续 PR 评估）

```
D:\Projects\Active\math2\
├── .agent/                       # AI 工程治理层（REPO_POLICY.md 等 6 份规范）
│   ├── AI_POLICY.md              # Agent 身份 / 权限 / 行为协议
│   ├── COMMAND_SAFETY.md         # 危险命令清单 + 三条强制前置
│   ├── ENVIRONMENT.md            # 仓库物理边界事实（repo root / flutter_app 是子目录）
│   ├── GIT_POLICY.md             # 分支/PR/merge 权限边界
│   ├── GIT_RULES.md              # git 红黄绿三级禁令
│   ├── REPO_POLICY.md            # 安全层总纲
│   ├── context/                  # 分级上下文加载规则
│   ├── templates/                # task-contract / commit message 模板
│   ├── tools/                    # guard.sh 机器强制层
│   └── state/                    # 运行时状态（gitignore，不入库）
├── .githooks/                    # Git hooks（core.hooksPath 指向）
├── .github/
│   └── workflows/                # CI workflow（ci.yml / branch-cleanup.yml / openwiki-update.yml 等）
├── .arts/                        # Arts 工具配置（settings.json，gitignore）
├── .adi/                         # ADI 运行时数据（gitignore）
├── .ffx/                         # ffx-cli 失败工件 + 缓存（gitignore）
├── .workbuddy/                   # WorkBuddy 工具产物（gitignore）
├── .wt/                          # worktree 占位（gitignore）
├── .codeartsdoer/                # IDE 工具目录（gitignore）
├── .claude/                      # Claude Code 项目级配置
│   ├── settings.json             # 项目级 hooks 配置（tracked）
│   └── hooks.log                 # 运行时日志（gitignore）
├── contracts/                    # 任务契约文件（11 个 tracked）
├── design-system/                # 设计 tokens 源（tracked）
├── docs/                         # 文档体系（四层信息架构，详见 INFO-ARCHITECTURE-DESIGN.md）
│   ├── README.md                 # 人类入口导航（按阅读目的）
│   ├── INDEX.md                  # 全量索引
│   ├── ROADMAP.md                # 路线图（Phase 0-4）
│   ├── INFO-ARCHITECTURE-DESIGN.md  # 信息架构设计
│   ├── MIGRATION-MAP.md          # 目录迁移映射
│   ├── product/                  # 产品真相（PRODUCT / UX-GUIDE / TYPORA-GAP / CAPABILITY-STATUS）
│   ├── architecture/             # 架构真相（ARCHITECTURE / EDITOR-MODEL / EXPORT-MODEL / UI-*）
│   ├── engineering/              # 工程真相（BASELINE / GATE-REPORT / RULES / WORKFLOW / VERIFICATION-POLICY）
│   ├── decisions/                # 决策真相（INDEX 状态表 + ADR/ 29 篇）
│   ├── contracts/                # 任务契约
│   ├── design/                   # 设计文档
│   ├── releases/                 # 11 篇 release notes
│   ├── regression/               # 回归用例包（BUG-001~003）
│   ├── evidence/                 # 证据索引（capability / visual / consumer）
│   ├── assets/                   # 文档资产
│   └── archive/                  # 历史档案（audits / runs / spikes / investigations / old-designs / governance）
├── formulafix-redesign.design/   # 设计稿（HTML，18 个 tracked）
├── openwiki/                     # OpenWiki 证据索引（gitignore, 由 GitHub Action 生成）
├── skills/                       # Skills 目录（tracked）
├── tests/                        # 顶层测试目录（tracked）
├── tools/                        # 工具链
│   ├── ffx-cli/                  # Python CLI（诊断 + ADI wrapper + markdown analysis）
│   │   └── cli_anything/ffx/
│   │       ├── ffx_cli.py        # Click 入口，--json/--project/--dry-run/--root
│   │       ├── core/             # project / adi_wrapper / session / contract_sync / docx_qa
│   │       ├── harness/          # 验证 / 评估 / 编排 / E8 视觉语义
│   │       ├── adapters/         # assets / base / formula / markdown / word / serializer
│   │       ├── utils/            # helpers
│   │       └── tests/            # 170+ pytest cases passing
│   └── adi/                      # Agent Diagnostic Interface（Dart CLI）
│       └── adi.dart
├── flutter_app/                  # Tafcm Flutter App（主项目）
│   ├── lib/                      # 业务代码（六层架构）
│   │   ├── main.dart
│   │   ├── core/                 # 基础设施（parser / renderers / services / router / utils）
│   │   ├── data/                 # 数据模型（Document / Template）
│   │   ├── domain/               # 业务领域（导出服务 / 业务 Provider）
│   │   ├── providers/            # 全局 Riverpod Provider
│   │   └── presentation/         # UI 组件、屏幕、主题
│   ├── test/                     # Unit + Widget tests（185 个测试文件 / ~1700+ 用例）
│   ├── integration_test/         # E2E tests（Android 模拟器 + 真机）
│   ├── tool/                     # preflight.sh / wsl_golden.sh
│   ├── docs/                     # Flutter 侧文档
│   └── pubspec.yaml
├── AGENTS.md                     # AI 协作开发强制规范（本文件）
├── README.md
├── LICENSE
├── .gitignore                    # 7 类规则（PR-1 起草 + PR-2 增量）
└── .gitattributes
```

#### 14.1.1 目录治理策略（v3 报告 §0.2 七维标准）

| 类别 | 治理方式 | 当前状态 |
|------|---------|---------|
| tracked source（业务代码） | intentional 跟踪 | ✅ main 已跟踪 17 个顶层 |
| project assets（设计稿 / 契约 / tokens / hooks） | intentional 跟踪 | ✅ design-system / contracts / formulafix-redesign.design / skills / tests / .githooks / .claude/settings.json 全部 tracked |
| runtime artifacts（.adi / .ffx / .workbuddy / .wt / openwiki / debug） | **gitignore 拦截** | ✅ PR-1 + PR-2 .gitignore 规则覆盖 |
| one-shot artifacts（ui_dump.xml / 一次性根目录 md） | **删除 + gitignore 防再生** | ✅ PR-2 已 git rm 3 个 + ignore /CLAUDE.md / **/ui_dump.xml |
| generated artifacts（openwiki/、CI logs） | **明确生成策略 + ignore** | ✅ openwiki/ 由 OpenWiki GitHub Action 生成，已 ignore |
| docs | current（PR-5 已同步 §14.1） | ✅ 本 PR 提交 |
| branches | separate governed state | ✅ PR-4 已删 4 本地 + 6 远端 ref |

### 14.2 技术栈速查

| 层级 | 技术 |
|------|------|
| 主 App | Flutter 3.44.6 / Dart >=3.0.0 / Riverpod 2.4.9 / go_router 12.x |
| CLI 工具 | Python 3.10+ / Click 8.x / pytest 9.x |
| 测试 | flutter_test / patrol（E2E）/ pytest |
| CI | GitHub Actions（ubuntu-24.04 / Flutter 3.44.6） |
| 诊断 | ADI (Agent Diagnostic Interface) / ffx-cli |

---

## 15. CLI Conventions（ffx-cli）

> **来源**：洞察报告显示 Click 的 `--json` flag 传播有多次回归，路径解析也踩过坑。

### 15.1 Flag 顺序规则

Click 框架要求 **flags 必须在前，subcommand 在后**：

```bash
# ✅ 正确
ffx --json project info -p project.json
ffx --json --root /path/to/project health
ffx --dry-run project create -o output.json

# ❌ 错误（flag 在 subcommand 之后不会被识别）
ffx project info --json -p project.json
```

### 15.2 通用验证命令

修改 ffx-cli 后**必须**执行：

```bash
# 跑全量 CLI 测试（170+ 用例，与 §14.1 一致）
cd tools/ffx-cli && python -m pytest cli_anything/ffx/tests/ -v

# 或单测某个模块
python -m pytest cli_anything/ffx/tests/test_core.py -v
```

### 15.3 已知历史坑（避免重踩）

| 问题 | 现象 | 教训 |
|------|------|------|
| `--json` 未传播 | 子命令输出不是 JSON | 必须用 `_effective_json(ctx)` 向上遍历 parent ctx |
| `_atomic_write` 路径错 | 写到错误目录 | 先 `Path(out_path).parent.mkdir(parents=True, exist_ok=True)` |
| `inject` 缺 type arg | `TypeError: inject_formula() missing 1 required positional argument` | Click option 加 `type=str` |
| `find_flutter_root` 找错目录 | 指向非公式项目 | 向上查找 `pubspec.yaml`，检查 `name: formula_fix` |

---

**本文档由首席架构工程师维护，版本 v0.4，生效日期 2026-08-17。**
<!-- 新增 §12-15：Bug Fix Protocol / Testing / Project Architecture / CLI Conventions -->
