# Development Guide（开发指南）

> 怎么开发 Tafcm——环境、日常流程、规范速查。
> 提炼自 [WORKFLOW.md](../engineering/WORKFLOW.md)、[DEVELOPMENT-RULES.md](../engineering/DEVELOPMENT-RULES.md)、[GIT-WORKFLOW.md](../engineering/GIT-WORKFLOW.md)。

## 1. 环境准备

```bash
# 前置：Flutter >= 3.44 / Dart >= 3.0
cd flutter_app && flutter pub get
flutter run              # Android 模拟器 / 桌面 / Web
flutter test             # 全量测试（~1700 用例）
```

工具链（可选）：`tools/ffx-cli`（Python 3.10+，`pip install -e .` 后 `ffx` 可用）。

## 2. 日常开发流程

1. **从 main 切分支**：`feat/<scope>-<desc>` / `fix/<scope>-<desc>` / `chore/<desc>` / `docs/<desc>`。
2. **改代码**：最小改动原则；改前读相关模块真实实现，不依赖文档描述。
3. **自测**（提交前必须）：
   ```bash
   cd flutter_app
   flutter analyze --no-fatal-infos --fatal-warnings   # 0 error / 0 warning
   flutter test test/<dir>/<file>_test.dart            # 先跑受影响文件
   ```
4. **提交**：Conventional Commits + `Task scope:` body。
5. **推送 + PR**：PR 描述含改动说明 / 测试方式 / 公共 API 影响 / 自测结果。

## 3. 编码规范速查

| 项 | 规则 |
|----|------|
| 类/枚举 | UpperCamelCase；文件 snake_case.dart |
| 文件头 | 1-3 行 `///` 职责说明 |
| 文件长度 | 超 400 行必须拆分 |
| import 顺序 | Dart SDK → Flutter/第三方 → 项目内（相对路径，不混 package:） |
| 空安全 | 禁止 `!` 强制解包（除非同行已 null 检查） |
| 注释 | dartdoc `///` 用于 public API；普通 `//` 实现细节；禁止无意义注释 |
| Provider | `xxxProvider` 后缀；禁止多文件同名定义 |
| 输出 | 禁止 `print()`，用 `debugPrint()` |

## 4. CI 流水线

Push / PR 触发：**Analyze → Test → ADI E2E → Golden → Build(apk+web) → Issue Triage**。

质量门禁（必须全绿）：`flutter analyze --no-fatal-infos --fatal-warnings`、`flutter test`、`flutter build apk --debug`、`flutter build web`。

**本地与 CI 差异提醒**：裸 `flutter analyze` 不把 warning 当 error；golden/perf 测试本地排除（`--exclude-tags golden --exclude-tags perf`），CI 在 Linux 上跑。

## 5. Code Review 流程

- PR 自动触发 Cline 审查（AGNES 网关）+ Copilot 审查（ruleset，main 分支）。
- Review 检查点：正确性 / 安全 / 可维护性 / 测试覆盖 / 接口兼容 / 文档同步。
- 结论：✅可以合并 / ⚠️建议修改后合并 / ❌需重大修改。

## 6. 常见坑（历史教训）

| 坑 | 教训 |
|----|------|
| SDK API 跨版本不稳 | 改前读 Flutter SDK 真实源码（`grep -n <symbol> <sdk>/packages/...`），不凭训练记忆 |
| 测试缺 `AppTheme.lightTheme` | 涉及 EditorTokens 的 Widget 测试必须注入主题，否则 `EditorTokens.of` 报错 |
| `ref.listen` 首帧不触发 | 用 `addPostFrameCallback` 调度 state 变更 |
| golden 基线过期 | 改显示文本/布局后跑 CI `update_goldens` 并提交 PNG |
| 命令行过长 | Windows 下分块跑 `flutter test`（`xargs -n 45`） |
