/// P0 真机问题守门测试：防止 focusOn viewState 缺失 + 字体文件名不匹配回归。
///
/// **背景**（phase3.5-realdevice-issues.md 问题 1+4+5）：
/// - 问题 1+5：CoordinatorState.focusOn 原代码在 curState == null 时跳过，
///   导致新块 viewState 缺失 → 无法进入编辑态 → IME 中断。
/// - 问题 4：pdf_exporter 加载 `NotoSansSC-Regular.ttf`，实际文件是 `NotoSansSC.ttf`。
///
/// **守门方式**：
/// - TC-P0-GUARD-1：focusOn 源码必须包含 `?? BlockViewState` 模式（防止改回 if-null-skip）
/// - TC-P0-GUARD-2：pdf_exporter 源码加载的字体文件名必须与 assets/fonts/ 实际文件匹配
/// - TC-P0-GUARD-3：focusOn 后 viewStateOf(id) 非 null 且 mode == editing（行为断言）
library;

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:formula_fix/core/editing/block_types.dart';
import 'package:formula_fix/presentation/states/block_view_state.dart';
import 'package:formula_fix/presentation/states/coordinator_state.dart';

void main() {
  group('TC-P0-GUARD-1: focusOn viewState 缺失修复（源码守门）', () {
    test('focusOn 方法包含 ?? BlockViewState 兜底模式', () {
      final file = File(
          'lib/presentation/states/coordinator_state.dart');
      final source = file.readAsStringSync();

      // 守门：必须包含 ?? BlockViewState 模式（防止改回 if (curState != null) 跳过模式）
      expect(
        source.contains('?? BlockViewState(id: id)'),
        isTrue,
        reason: 'focusOn 必须用 ?? BlockViewState(id: id) 兜底，'
            '防止 curState == null 时跳过导致 viewState 缺失',
      );
    });

    test('focusOn 方法不包含 if (curState != null) 跳过模式', () {
      final file = File(
          'lib/presentation/states/coordinator_state.dart');
      final source = file.readAsStringSync();

      // 守门：不包含旧的跳过模式（curState != null 时才更新）
      // 注意：focusOn 方法体内的 curState 检查不应有 if-null-guard
      final focusOnSection = source.substring(
        source.indexOf('CoordinatorState focusOn('),
        source.indexOf('clearFocusOf'),
      );
      expect(
        focusOnSection.contains('if (curState != null)'),
        isFalse,
        reason: 'focusOn 不应包含 if (curState != null) 跳过模式，'
            '该模式导致新块 viewState 缺失（真机问题 1+5 根因）',
      );
    });
  });

  group('TC-P0-GUARD-2: PDF 导出中文字体文件名匹配', () {
    test('pdf_exporter 加载的字体文件名存在于 assets/fonts/ 目录', () {
      final exporterSource = File(
              'lib/domain/services/exporters/pdf_exporter.dart')
          .readAsStringSync();

      // 提取 rootBundle.load('assets/fonts/XXX.ttf') 中的文件名
      final match = RegExp(r"rootBundle\.load\('assets/fonts/([^']+)'\)")
          .firstMatch(exporterSource);
      expect(match, isNotNull,
          reason: 'pdf_exporter 应通过 rootBundle.load 加载字体');
      final fontFile = match!.group(1)!;

      // 验证文件实际存在
      final file = File('assets/fonts/$fontFile');
      expect(
        file.existsSync(),
        isTrue,
        reason: 'assets/fonts/$fontFile 不存在！'
            'pdf_exporter 加载的字体文件名必须与实际文件匹配（真机问题 4 根因）',
      );
    });

    test('pdf_exporter 不加载 NotoSansSC-Regular.ttf（已知的错误文件名）', () {
      final exporterSource = File(
              'lib/domain/services/exporters/pdf_exporter.dart')
          .readAsStringSync();

      expect(
        exporterSource.contains('NotoSansSC-Regular.ttf'),
        isFalse,
        reason: 'NotoSansSC-Regular.ttf 不存在于 assets/fonts/，'
            '实际文件名是 NotoSansSC.ttf（真机问题 4 根因）',
      );
    });
  });

  group('TC-P0-GUARD-3: focusOn 行为断言', () {
    test('focusOn 对任意 id 都产生 editing 态 viewState', () {
      // 遍历多种初始状态，确保 focusOn 始终正确
      final testCases = <CoordinatorState>[
        const CoordinatorState.empty(),
        CoordinatorState.initial({
          const BlockId('a'): const BlockViewState(id: BlockId('a')),
        }),
        CoordinatorState(
          viewStates: Map.unmodifiable({
            const BlockId('a'): const BlockViewState(
              id: BlockId('a'),
              isFocused: true,
              mode: RenderMode.editing,
            ),
          }),
          focusedId: const BlockId('a'),
        ),
      ];

      for (int i = 0; i < testCases.length; i++) {
        final state = testCases[i];
        const target = BlockId('target');
        final next = state.focusOn(target);

        expect(next.focusedId, equals(target),
            reason: 'case $i: focusedId 应指向 target');
        expect(next.viewStateOf(target), isNotNull,
            reason: 'case $i: viewStateOf(target) 不应为 null');
        expect(next.viewStateOf(target)!.mode,
            equals(RenderMode.editing),
            reason: 'case $i: mode 应为 editing');
        expect(next.viewStateOf(target)!.isFocused, isTrue,
            reason: 'case $i: isFocused 应为 true');
      }
    });
  });
}