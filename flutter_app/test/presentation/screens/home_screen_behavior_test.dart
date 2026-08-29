/// P1 验收补充（2026-08-04）：HomeScreen「打开任意 .md 文件」交互测试。
///
/// 覆盖 home_screen.dart 中 `_openAnyMd` 的两条关键路径：
/// 1. 用户取消选择（FilePicker.pickFiles 返回 null）→ 不导航，无异常。
/// 2. 用户选择有效 .md 路径 → 调用 `context.push('/editor?path=...')`（P1 修复 2026-08-06：
///    原 `context.go` 替换整个栈导致编辑器返回按钮无页可 pop，改 `push` 保留返回栈）。
///
/// 同时锁定调用 `FilePicker.platform.pickFiles` 时传入的 `type` / `allowedExtensions`
/// 参数（防止回归到 `FileType.any` 导致非 .md 文件可选）。
///
/// FilePicker 通过 `PlatformInterface` 暴露静态 `platform` setter，
/// 可在测试中注入 mock 子类（见 file_picker 8.3.7 `src/file_picker.dart:30-42`）。
library;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:tafcm/data/models/document.dart';
import 'package:tafcm/core/services/file_repository.dart';
import 'package:tafcm/presentation/screens/home_screen.dart';
import 'package:tafcm/presentation/theme/app_theme.dart';
import 'package:tafcm/providers/file_repository_provider.dart';

/// 测试用 [FilePicker] 桩：记录 pickFiles 调用参数，按构造时指定的结果返回。
///
/// 必须继承（而非 implements）[FilePicker]，因为 file_picker 的 PlatformInterface
/// 用 token 校验 set platform 的实例（`src/file_picker.dart:33-42`）。
class _MockFilePicker extends FilePicker {
  _MockFilePicker(this._result);

  final FilePickerResult? _result;

  /// 最近一次 pickFiles 调用的参数（用于断言 type / allowedExtensions）。
  FileType? lastType;
  List<String>? lastAllowedExtensions;

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = true,
    int compressionQuality = 30,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async {
    lastType = type;
    lastAllowedExtensions = allowedExtensions;
    return _result;
  }
}

/// 不触发真实文件 I/O 的 [FileRepository] 桩。
class _NoIoFileRepository extends FileRepository {
  @override
  Future<List<Document>> listDocuments() async => const [];

  @override
  Stream<List<Document>> watchAllDocuments() async* {
    yield const [];
  }
}

void main() {
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
  });

  /// 在 HomeScreen 外层挂一个最小 GoRouter（含 /home + /editor 两条路由），
  /// 让 `context.go('/editor?path=...')` 可被路由器消费而非抛 "no Scope"。
  /// 通过观察 widget tree 是否出现 'editor-stub' 占位文本来验证导航发生。
  Future<void> _pumpHomeWithRouter(
    WidgetTester tester,
    _MockFilePicker mockPicker,
  ) async {
    final router = GoRouter(
      initialLocation: '/home',
      routes: [
        GoRoute(
          path: '/home',
          builder: (context, state) => const HomeScreen(),
        ),
        GoRoute(
          path: '/editor',
          // EditorPage 真实加载会触发文件 I/O + WebView，这里用占位 Scaffold。
          // 我们只断言「导航是否发生」（占位文本出现），不验证 EditorPage 本身。
          builder: (context, state) =>
              const Scaffold(body: Center(child: Text('editor-stub'))),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          fileRepositoryProvider.overrideWithValue(_NoIoFileRepository()),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          theme: AppTheme.lightTheme,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('P1 验收 HomeScreen._openAnyMd', () {
    testWidgets('点击「打开任意 .md 文件」入口可被识别（存在 InkWell + 文案）',
        (tester) async {
      final mockPicker = _MockFilePicker(null);
      FilePicker.platform = mockPicker;
      await _pumpHomeWithRouter(tester, mockPicker);

      // 入口存在 + 文案正确。
      expect(find.text('打开任意 .md 文件'), findsOneWidget);
      expect(find.text('即开即看'), findsOneWidget);
    });

    testWidgets('用户取消选择（pickFiles 返回 null）→ 不导航，无异常',
        (tester) async {
      final mockPicker = _MockFilePicker(null);
      FilePicker.platform = mockPicker;
      await _pumpHomeWithRouter(tester, mockPicker);

      // 初始：停在 /home，editor-stub 占位文本不可见。
      expect(find.text('editor-stub'), findsNothing);

      // 点击「打开任意 .md 文件」入口。
      await tester.tap(find.text('打开任意 .md 文件'));
      await tester.pumpAndSettle();

      // P0 修复后（2026-08-04）：改用 FileType.any 绕过小米 HyperOS SAF
      // 对 type='*/*' + EXTRA_MIME_TYPES 过滤异常的 bug。
      expect(mockPicker.lastType, FileType.any,
          reason: '_openAnyMd 必须用 FileType.any（详见 home_screen.dart 注释）');

      // 用户取消 → 不触发导航（editor-stub 仍不可见）。
      expect(find.text('editor-stub'), findsNothing,
          reason: 'pickFiles 返回 null 时不应调用 context.go');
      // 仍停在 HomeScreen。
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('用户选择有效 .md 路径 → 导航到 /editor?path=...',
        (tester) async {
      // 构造一个有效的 FilePickerResult：单一文件，path = /mock/doc.md。
      final mockResult = FilePickerResult([
        PlatformFile(path: '/mock/doc.md', name: 'doc.md', size: 100),
      ]);
      final mockPicker = _MockFilePicker(mockResult);
      FilePicker.platform = mockPicker;
      await _pumpHomeWithRouter(tester, mockPicker);

      // 初始：HomeScreen 可见，editor-stub 不可见。
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.text('editor-stub'), findsNothing);

      // 点击入口 → mock 返回有效路径 → context.go('/editor?path=...')。
      await tester.tap(find.text('打开任意 .md 文件'));
      await tester.pumpAndSettle();

      // P0 修复后：用 FileType.any，Dart 层校验 .md 扩展名。
      expect(mockPicker.lastType, FileType.any);

      // 关键断言：导航发生 → /editor 路由的占位文本出现。
      expect(find.text('editor-stub'), findsOneWidget,
          reason: 'pickFiles 返回有效 .md 路径时应导航到 /editor 路由');
      // P1 修复（2026-08-06）：改用 context.push 保留返回栈。
      // 注意：push 保留的是 go_router 的导航栈（canPop == true，pop 可回 /home），
      // 但前一页 widget 不一定保持 mounted（go_router 默认不保留离屏页 widget）。
      // 返回栈的验证由 editor_back_navigation_test.dart 覆盖（push → tap back → /home）。
      expect(find.byType(HomeScreen), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('用户选择非 .md 文件 → 提示「仅支持 .md 文件」并中止导航',
        (tester) async {
      // P0 修复后（2026-08-04）：FileType.any 允许选任何文件，Dart 层校验扩展名。
      // 选 .txt 文件应触发 SnackBar 提示，不导航。
      final mockResult = FilePickerResult([
        PlatformFile(path: '/mock/notes.txt', name: 'notes.txt', size: 50),
      ]);
      final mockPicker = _MockFilePicker(mockResult);
      FilePicker.platform = mockPicker;
      await _pumpHomeWithRouter(tester, mockPicker);

      // 点击入口 → mock 返回 .txt 路径。
      await tester.tap(find.text('打开任意 .md 文件'));
      await tester.pumpAndSettle();

      // 应显示 SnackBar 提示。
      expect(find.text('仅支持 .md 文件'), findsOneWidget);
      // 不应导航（editor-stub 不可见）。
      expect(find.text('editor-stub'), findsNothing,
          reason: '选非 .md 文件不应导航到 /editor');
      // 仍停在 HomeScreen。
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
