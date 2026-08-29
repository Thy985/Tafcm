# Debugging Guide（调试指南）

> 怎么排查问题——诊断工作流、工具入口、常见坑。
> 提炼自 [ADR-0024](../decisions/ADR/0024-agent-diagnostic-interface.md)（ADI）、AGENTS.md §9.5 / §11（CI 失败手册）、.agent/COMMAND_SAFETY.md。

## 1. 诊断工作流（ADI，先证据后假设）

Agent 调试 Tafcm 时的强制顺序（Agent Interaction Contract，ADR-0024 §1.4）：

```bash
# 1. Query first —— 取 Observation，不凭空假设
dart run tools/adi/adi.dart latest-error --json

# 2. Inspect before edit —— 先看因果链再改代码
dart run tools/adi/adi.dart trace show <id>

# 3. Replay before modify —— 不能复现的 bug 不应修
dart run tools/adi/adi.dart replay <id>

# 4. Validate after modify —— 改完验证闭环
dart run tools/adi/adi.dart validate --after-fix
```

**关键纪律**：
- `candidate_causes` 是假设不是结论，修复决策需自行推理。
- `invariant_report.violated` 非空 = 状态损坏（真 bug）；全通过 = 渲染降级或既定行为（ADR-0022）。
- 复测守护：改代码前先跑 failing test 复现，改后跑同一测试验证。

## 2. 工具入口

| 工具 | 用途 | 入口 |
|------|------|------|
| ADI | 诊断采集 + 因果链 + 闭环验证 | `dart run tools/adi/adi.dart` |
| ffx-cli | 项目分析 / 契约校验 / 验证编排 | `cd tools/ffx-cli && ffx <cmd>` |
| 诊断 zip | 运行时快照（snapshot.json + 日志） | 应用内"诊断导出"→ 分析 zip |
| flutter logs | 渲染 / 异常现场 | `flutter run` 终端 + `debugPrint` 输出 |

## 3. 常见问题排查

### 3.1 CI Analyze 失败

```bash
cd flutter_app && flutter analyze --no-fatal-infos --fatal-warnings
# 症状：unused_import / undefined_* / depend_on_referenced_packages
# 常见根因：删字段未删 import；分支基于旧 base 合并引入旧引用
```

### 3.2 CI Test 失败

```bash
# 症状：Widget 测试报 EditorTokens 未注入 → 测试补 theme: AppTheme.lightTheme
# 症状：SnackBar/Overlay 找不到 → ref.listen 首帧不触发，用 addPostFrameCallback
# 症状：架构守门 file_access_test 失败 → presentation 层禁直接 File()/writeAsBytes
```

### 3.3 渲染 / 公式问题

- 公式异常：查 `FormulaSvgService` 渲染路径；降级路径（flutter_math）是否触发；导出走 SVG 矢量硬约束。
- Mermaid 冷启动 2-3s 属已知；单条公式 30s 超时属已知边界。
- 用户输入路径任何层不 crash（ADR-0022 原则）——见到 UnimplementedError 即违规。

### 3.4 环境级干扰（本仓库 Windows 特有）

- Defender 实时删除工作树：只影响全量 `flutter` 套件；单文件 `flutter test <file>` 可正常跑。
- `flutter.bat` 在 PowerShell 下 stdout 缓冲死锁：用 Git Bash。
- CI log 拉取偶发 EOF / timeout：重试；golden artifact 用 `gh run download -n golden-baselines`。

## 4. 已知边界（非 bug，排查时先排除）

| 项 | 边界 |
|----|------|
| 编辑/预览分离模式 | 历史遗留，目标态单 WYSIWYG 视图 |
| 导出 Word 生态冲突 | docx_creator 依赖链与项目锁冲突，Word 走自研 OOXML |
| WebView 冷启动 / 公式超时 | 见 3.3 |
| golden 本地失败 | Windows 基线差异，CI Linux 为准 |

## 5. 修复纪律

- 一个 PR 只修一个问题；最小改动。
- 修复必须补回归测试或更新 skip 登记（TEST_SKIP_REGISTRY）。
- 修完跑：`flutter analyze` + 对应单文件测试 + 相关架构守门。
