/// DocumentListScreen — Phase 3.4 Slice 6 / 3.4.2 文件树侧栏（PR #77）。
///
/// **占位声明**：与 [EditorTokens] 同样原因 — main 02afb030 的 tree 引用了 missing
/// blob（SHA 23a03e19…），本目录提供一个最小占位 [DocumentListScreen] 让
/// `import 'package:formula_fix/presentation/screens/document_list_screen.dart';`
/// 解析通过，同时满足
/// `test/router_integration_test.dart: DocumentListScreen 可构建，AppBar 显示"FormulaFix"`
/// 守门（避免 owner merge 时 PR #78 引入回归）。PR #78 不直接引用本类的具体 UI 行为，
/// owner merge 后若 main 仓库能 fetch 真实 blob 应恢复。
library;

import 'package:flutter/material.dart';

/// 文件管理 / 文档列表页（占位 — 真实实现见 main PR #77）。
class DocumentListScreen extends StatelessWidget {
  const DocumentListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('FormulaFix')),
      body: const Center(
        // 占位文案明确标识 PR #78 重构期间临时态，便于 owner merge 后识别。
        child: Text('DocumentListScreen（PR #78 占位）'),
      ),
    );
  }
}
