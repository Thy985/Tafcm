# FormulaFix

> 移动端 Typora 类 Markdown 写作工具，以公式 / 图表 / 学术写作为特色。
> 目标：让手机端也能拥有 Typora 级别的所见即所得（WYSIWYG）写作体验。

[![CI](https://github.com/Thy985/Tafcm/actions/workflows/ci.yml/badge.svg)](https://github.com/Thy985/Tafcm/actions/workflows/ci.yml)
[![Phase](https://img.shields.io/badge/phase-3.12%20Info%20Architecture-blue)](docs/ROADMAP.md)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)

---

## 这是什么

FormulaFix 不是"带预览的 Markdown 编辑器"，而是 **移动端 Typora 类产品**：

- ✅ **所见即所得**：块级 WYSIWYG 编辑，无"编辑/预览"模式切换
- ✅ **手机优先**：为触屏 + 单手握持重新设计的交互范式
- ✅ **学术写作特色**：原生支持 LaTeX 公式、Mermaid 图表、代码高亮
- ✅ **便携查看器**：任意来源 .md 文件即开即看，无需导入到 Vault
- ✅ **离线可用**：100% 本地渲染，无云端依赖
- ✅ **多平台**：Android / Windows / Web

## 核心能力

| 能力 | 说明 | 完成度 |
|------|------|--------|
| Markdown 解析 / 序列化 | 手写 parser（AST 驱动）+ round-trip fuzz 守护 | ✅ 完整 |
| 块级 WYSIWYG 编辑 | 8 种 BlockType + Transaction 模型 + Undo/Redo | ✅ 完整 |
| 公式渲染 | LaTeX → SVG 矢量 + PNG 回退（E6 真机验证） | ✅ 完整 |
| Mermaid 图表 | WebView 渲染 → SVG 嵌入导出 | ✅ 完整 |
| 导出 | Markdown / Word / PDF / 文本（SVG 矢量硬约束） | ✅ 完整 |
| 主题 | Light / Dark / Sepia（Design System Token 驱动） | ✅ 完整 |
| 可观测 / ADI | 渲染追踪 + Agent Diagnostic Interface + FFX 验证编排 | ✅ 完整（Phase 3.7-3.11） |

详细能力状态见 [docs/product/CAPABILITY-STATUS.md](docs/product/CAPABILITY-STATUS.md)（人类视图）
与 [contracts/*.json](contracts/)（机器视图）。

## 当前状态

**Phase 0-3.11 全部完成**；Phase 3.11（Capability Hardening Loop）已按 PHASE_3_11_EXIT 判定关闭（2026-08-22）。
当前处于 **Phase 3.12：信息架构重构**（2026-08-27，本文件即为该阶段产物）。

工程地基五维状态（2026-08-22 冻结）：

| 维度 | 状态 |
|------|------|
| Engineering Foundation | ✅ ~95%（编辑内核 / 块运行时 / 持久化 / 导出 / 可观测 / E2E） |
| Capability Coverage | ✅ COMPLETE（F1-F4 四能力族全部验证） |
| Runtime Validation | ✅ FULLY VALIDATED（Formula Real Defect Loop 闭环） |
| E6/E8 Evidence | ✅ RELEASE-GATE SATISFIED（真机 zorn 4/4 PASS + E8 视觉语义验证） |
| Visual / Product Identity | 🟡 ~60%（UI 修复 P2-P3 进行中） |

## 核心架构

```
Markdown
   ↓
Parser（手写，AST 驱动）
   ↓
Document AST（sealed DocumentElement）
   ↓
Live / Committed 双状态（ADR-0012）
   ↓
Transaction（操作日志 / commit-rollback / coalescing，ADR-0008）
   ↓
History（Undo/Redo）
   ↓
Renderer（Block → Widget，公式 → SVG/PNG）
   ↓
Export（Markdown / Word / PDF / 文本）

—— Agent Engineering 闭环 ——
ADI（诊断采集）→ FFX（验证编排）→ contracts/（能力契约）→ regression/（回归资产）
```

六层分层架构（`core → data → domain → providers → presentation`）：
`flutter_app/lib/` 内严格自上而下依赖，循环依赖零容忍（详见 [AGENTS.md](AGENTS.md) §1）。

## 快速开始

```bash
# 1. 安装 Flutter（>= 3.44）与 Dart（>= 3.0）
# 2. 拉取依赖
cd flutter_app && flutter pub get
# 3. 运行（Android 模拟器 / 桌面 / Web）
flutter run
# 4. 跑测试
flutter test
# 5. Agent 验证编排（可选）
cd tools/ffx-cli && python -m pytest cli_anything/ffx/tests/
```

## 文档入口

| 入口 | 用途 |
|------|------|
| [docs/README.md](docs/README.md) | **文档门户**：按阅读目的导航（新人 / 改代码 / 查决策 / 验证 / 追溯历史） |
| [docs/decisions/INDEX.md](docs/decisions/INDEX.md) | **ADR 索引**：架构决策状态总表（29 篇） |
| [docs/architecture/ARCHITECTURE.md](docs/architecture/ARCHITECTURE.md) | 当前架构总览（只讲"现在是什么"） |
| [docs/product/CAPABILITY-STATUS.md](docs/product/CAPABILITY-STATUS.md) | 当前能力完成度（人类视图） |
| [docs/engineering/ENGINEERING-BASELINE.md](docs/engineering/ENGINEERING-BASELINE.md) | 工程基线 + 已知债务（DEBT 表） |
| [docs/ROADMAP.md](docs/ROADMAP.md) | 路线图（Phase 0-4） |
| [AGENTS.md](AGENTS.md) | **AI 协作规范**（架构原则 / 编码规范 / 禁止事项 / CI 失败手册） |
| [.agent/CURRENT-STATE.md](.agent/CURRENT-STATE.md) | Agent 当前状态入口 |

## 验证入口

| 资产 | 位置 |
|------|------|
| 能力契约（机器可读） | [contracts/*.json](contracts/)（11 个） |
| 回归资产（可核对 case 包） | [docs/regression/](docs/regression/) |
| 证据资产（截图 + 判定，可追溯） | [docs/evidence/](docs/evidence/) |
| 视觉基线（golden） | `flutter_app/test/golden/` |
| 运行时产物（不入库） | `.adi/` |

## License

本项目基于 [MIT 协议](LICENSE) 开源。

Copyright (c) 2026 [Thy985](https://github.com/Thy985)

---

**维护人**：首席架构工程师
**最近更新**：2026-08-27
**文档版本**：v1.0（Phase 3.12 信息架构重构）
