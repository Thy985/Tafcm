# Contributing to Tafcm

> 社区/协作者入口——先读本页，再读 [Engineering Handbook](docs/ENGINEERING.md)。
> 本文档提炼自 [.agent/GIT_POLICY.md](.agent/GIT_POLICY.md) 与 [docs/engineering/GIT-WORKFLOW.md](docs/engineering/GIT-WORKFLOW.md)；完整强制规则以 AGENTS.md 为准。

## 1. 项目速览

- **产品**：Tafcm —— 移动端 Typora 类排版写作工具（Typeset · Agent-native · Formula-aware · CLI-native · Markdown-first）。
- **代码**：Flutter（`flutter_app/`）+ 工具链（`tools/ffx-cli`）。
- **知识入口**：[Engineering Handbook](docs/ENGINEERING.md)。
- **发布状态**：Phase 3 系列完成，处于阶段间空档期；APK 尚未正式发布（见 [CHANGELOG.md](CHANGELOG.md)）。

## 2. 环境准备

```bash
# Flutter >= 3.44 / Dart >= 3.0
cd flutter_app && flutter pub get
flutter run              # Android 模拟器 / 桌面 / Web
flutter test             # 全量测试（~1700 用例）
```

## 3. 分支与提交规范

- 分支命名：`feat/<scope>-<desc>` / `fix/<scope>-<desc>` / `chore/<desc>` / `docs/<desc>`；必须从 `main` 切出。
- 提交信息：Conventional Commits（`feat` / `fix` / `refactor` / `docs` / `chore` …），body 标注任务范围。
- **禁止**直接 push `main`；所有改动走 PR。
- 禁止提交：`build/`、`.dart_tool/`、含密钥文件、一次性调试文件。

## 4. PR 检查清单

- [ ] 关联 issue 编号（如有）
- [ ] 改动说明（what + why）
- [ ] 测试方式（手动 / 自动）
- [ ] 是否影响公共 API
- [ ] 是否更新文档
- [ ] 自测：`flutter analyze --no-fatal-infos --fatal-warnings` 0 error / 0 warning
- [ ] 自测：`flutter test` 全量通过
- [ ] 涉及 Android：`flutter build apk --debug` 成功

## 5. 行为约定

- **最小改动**：能改一行不改两行；不顺手重构无关代码。
- **测试纪律**：新功能必须有测试；bug 修复必须有回归测试；禁止删除测试以通过 CI。
- **架构纪律**：改动不得破坏六层依赖（`core → data → domain → providers → presentation`）；架构决策先落 ADR。
- **不确定时**：先问，不自行假设（见 [Agent Collaboration](docs/principles/agent-collaboration.md)）。

## 6. 反馈渠道

- Bug / 功能建议：GitHub Issues（issue triage 自动分类）。
- 自动审查：PR 触发 Cline 审查（AGNES 网关）+ Copilot 审查（ruleset）。
