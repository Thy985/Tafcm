# Tafcm：移动端 WYSIWYG Markdown 编辑器的架构实践（Flutter + Riverpod）

> 一个开源项目，把 Typora 级的排版体验搬到手机上：所见即所得（WYSIWYG）、公式 / 图表 / 学术写作特色、任意 .md 即开即看。

## 为什么做移动端 WYSIWYG

移动端 Markdown 写作的现状：多数 App 是"编辑 + 预览"分离模式，改一行切一次屏；公式渲染要么不支持、要么脱离编辑器；`.md` 文件往往要先导入专属格式才能打开。

Tafcm 的目标很直接：**手机上看到什么，就是最终的样子**。块级 WYSIWYG 编辑，公式 / Mermaid / 表格 / 代码块在编辑界面直接渲染成型。

## 技术栈总览

| 层 | 选型 |
|----|------|
| UI | Flutter 3.44（Material 3，Android 优先） |
| 状态管理 | Riverpod（StateNotifier / Provider / FutureProvider 决策树） |
| Markdown 解析 | 手写 parser（AST 驱动，无第三方） |
| 公式渲染 | 编辑器内 SVG 矢量（MathJax via WebView）+ PNG 位图回退 |
| 图表 | Mermaid（WebView 渲染 → SVG 嵌入） |
| PDF 导出 | dart_pdf（矢量 SVG 嵌入） |

## 六层分层架构

```
presentation/   UI 组件、屏幕、主题
providers/      全局 Riverpod Provider
domain/         业务领域（导出服务、业务 Provider）
data/           数据模型（Document / Template）
core/           基础设施（parser / renderers / services）
main.dart       App 入口
```

强制规则：**core 不允许反向 import 上层**；循环依赖零容忍（有架构测试守门：`test/architecture/layer_dependency_test.dart`）。

## 关键实现一：AST 驱动的 Markdown 解析

手写 parser，产出 sealed class 联合的 Document AST，配合 Dart 3 模式匹配：

```dart
sealed class DocumentElement { ... }
final class HeadingElement extends DocumentElement { final int level; ... }
final class FormulaElement extends InlineElement { final String latex; ... }

// 渲染分支：switch + 模式匹配，编译器保证穷尽
pw.Widget render(InlineElement e) => switch (e) {
  TextElement() => Text(e.text),
  FormulaElement() => FormulaView(e.latex),
  BoldElement() => Bold(child: render(e.children)),
  ...
};
```

优势：解析与渲染解耦、round-trip 序列化（`.md` 文件为单一真相源）、AST 等价性测试守护。

## 关键实现二：公式渲染双路径

- **编辑器内**：MathJax 经 WebView 渲染为 SVG → Dart 读回 → 矢量呈现（缩放无损）
- **导出兜底**：`buildFormulaPlan` 决策链——缓存 SVG → 缓存 PNG → 离屏渲染 → 文本 fallback，任一环节失败不阻塞整份导出

## 关键实现三：导出组装有限性（一次真实 bug 的教训）

真机复现了一个棘手的卡死：30 块 + 12 个公式 SVG 的 PDF 组装（`addPage` 同步布局）**永久阻塞**，进度停在 28%，而纯 Dart 环境同密度 30s 内完成——真机环境特有。

定位为 blocking primitive（多公式 SVG 密度）后，落地了**有限性保证**（ADR-0032）：

1. **预防性降级**（主要机制）：分片渲染时统计片内公式数，≥ 阈值（8）→ 该片公式降级为文本 fallback，从根上避免多公式 SVG 布局触发卡死
2. **watchdog 检测**（兜底）：`addPage` 期间 3s 定时器置位阻塞标志，返回后检测并报告
3. **结果**：卡死场景从 60s+ → 270ms 完成，导出必定进入终态

工程启示：**同步布局无法被外部中断**——有限性不能依赖"超时后恢复"，而要在进入危险路径前预防。

## 工程实践：CI 与可观测

- CI 门禁四件套：`flutter analyze --fatal-warnings` / `flutter test`（185 文件 / 1700+ 用例）/ `build apk` / `build web` 全绿
- **ADR 决策记录**：29 篇架构决策（ADR-0001 ~ 0032），每个决策有背景 / 动机 / 后果 / 替代方案
- **ADI 诊断接口**：Agent Diagnostic Interface，把渲染卡死 / 导出异常采集为可复现的诊断链
- **架构测试守门**：分层依赖方向 / 文件行数（400 行拆分）/ Provider 唯一性 / presentation 禁文件 I/O

## 开源与路线图

- 项目：https://github.com/Thy985/Tafcm（MIT 协议，v0.1.1 已发布）
- 下载：https://github.com/Thy985/Tafcm/releases/tag/v0.1.1（release 99MB / debug 231MB）
- 当前：Phase 3.12 信息架构重构；规划：编辑体验打磨 → 更多导出格式 → 多平台

移动端 WYSIWYG 是个有挑战的领域（触屏交互、公式排版、真机渲染差异），欢迎一起折腾。
