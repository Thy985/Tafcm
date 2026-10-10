/// issue #330 外部导入 .md 只读查看 — widget 测试。
///
/// 覆盖：
///   1. `readOnly: true` 打开外部 .md → 只读横幅出现（编辑已禁用提示）。
///   2. `readOnly: false` 打开库内 .md → 无只读横幅（库内文档保持可写）。
///   3. `readOnly: true` 不写 currentPathProvider（自动保存对非库内文件 inert）。
///
/// 用内存 fake 仓储（零真实 I/O）+ 固定时长 pump（真实编辑器含光标闪烁
/// 动画，pumpAndSettle 永不收敛——同 editor_page_missing_file_test 的既有
/// 结论）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview_platform_interface/flutter_inappwebview_platform_interface.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:tafcm/core/document_repository.dart';
import 'package:tafcm/data/models/document.dart';
import 'package:tafcm/presentation/editor/editor_page.dart';
import 'package:tafcm/providers/current_path_provider.dart';
import 'package:tafcm/providers/file_repository_provider.dart';
import 'package:tafcm/presentation/theme/app_theme.dart';

/// 测试用 `InAppWebViewPlatform` 桩（与 export_back_confirm_widget_test 同源）。
class _FakeInAppWebViewPlatform extends InAppWebViewPlatform {
  @override
  PlatformInAppWebViewWidget createPlatformInAppWebViewWidget(
    PlatformInAppWebViewWidgetCreationParams params,
  ) {
    return _NoopPlatformInAppWebViewWidget(params);
  }
}

class _NoopPlatformInAppWebViewWidget extends PlatformInAppWebViewWidget {
  _NoopPlatformInAppWebViewWidget(super.params) : super.implementation();

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();

  @override
  T controllerFromPlatform<T>(PlatformInAppWebViewController controller) {
    throw UnimplementedError(
        'NoopPlatformInAppWebViewWidget.controllerFromPlatform');
  }

  @override
  void dispose() {}
}

/// 内存 fake：`readDocument` 返回固定文档，其余行为不被测试触达。零真实 I/O。
class _FakeDocRepository implements DocumentRepository {
  @override
  Future<Document> readDocument(String path) async => Document(
        id: 'external-doc',
        title: '外部文档',
        content: '# 外部文档\n\n可编辑查看测试。',
        createdAt: DateTime(2026, 10, 4),
        updatedAt: DateTime(2026, 10, 4),
      );

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} 不应被本测试触达');
}

const _bannerText = '查看模式 · 外部文件不可保存，编辑已禁用';
const _docPath = '/sentinel/documents/external_big.md';

void main() {
  setUpAll(() {
    InAppWebViewPlatform.instance = _FakeInAppWebViewPlatform();
    SharedPreferences.setMockInitialValues({});
  });

  Future<ProviderContainer> pumpEditor(
    WidgetTester tester, {
    required bool readOnly,
  }) async {
    final container = ProviderContainer(
      overrides: [
        fileRepositoryProvider.overrideWithValue(_FakeDocRepository()),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: EditorPage(filePath: _docPath, readOnly: readOnly),
        ),
      ),
    );
    // 不用 pumpAndSettle：编辑器含光标闪烁动画，永不收敛（同既有测试结论）。
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(seconds: 1));
    return container;
  }

  testWidgets('1. readOnly=true 外部文件 → 只读横幅出现', (tester) async {
    await pumpEditor(tester, readOnly: true);
    expect(find.text(_bannerText), findsOneWidget,
        reason: '外部文件应显示只读横幅（编辑已禁用提示）');
    expect(tester.takeException(), isNull);
  });

  testWidgets('2. readOnly=false 库内文件 → 无只读横幅（保持可写）',
      (tester) async {
    await pumpEditor(tester, readOnly: false);
    expect(find.text(_bannerText), findsNothing,
        reason: '库内文档（可写路径）不应出现只读横幅');
    expect(tester.takeException(), isNull);
  });

  testWidgets('3. readOnly=true 不写 currentPathProvider（autosave inert）',
      (tester) async {
    final container = await pumpEditor(tester, readOnly: true);
    expect(container.read(currentPathProvider), isNull,
        reason: '只读外部文件不注册持久化路径，自动保存对非库内文件 inert');
  });
}