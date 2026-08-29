import 'package:flutter_test/flutter_test.dart';
import 'package:tafcm/core/editing/block_types.dart';
import 'package:tafcm/presentation/blocks/shared/block_convert.dart';

/// applyBlockPrefix 纯函数单测（T1-4）。
///
/// 覆盖多行前缀剥离 / 添加、列表前缀剥离、空字符串等边界——
/// widget 层（block_interaction_test）只走单行路径，此处补全矩阵。
void main() {
  group('applyBlockPrefix → paragraph（仅去前缀）', () {
    test('多行 blockquote 全行剥 >', () {
      expect(
        applyBlockPrefix('> line one\n> line two\n> line three',
            BlockType.paragraph),
        'line one\nline two\nline three',
      );
    });

    test('heading 前缀剥离（## 多井号）', () {
      expect(applyBlockPrefix('## Title', BlockType.paragraph), 'Title');
    });

    test('列表前缀剥离（- / * / +）', () {
      expect(applyBlockPrefix('- item', BlockType.paragraph), 'item');
      expect(applyBlockPrefix('* item', BlockType.paragraph), 'item');
      expect(applyBlockPrefix('+ item', BlockType.paragraph), 'item');
    });

    test('无前缀正文保持不变', () {
      expect(applyBlockPrefix('plain text', BlockType.paragraph),
          'plain text');
    });

    test('空字符串不崩溃', () {
      expect(applyBlockPrefix('', BlockType.paragraph), '');
    });
  });

  group('applyBlockPrefix → blockquote（每行加 >）', () {
    test('多行 paragraph 全行加 >', () {
      expect(
        applyBlockPrefix('line one\nline two', BlockType.blockquote),
        '> line one\n> line two',
      );
    });

    test('## 标题转 blockquote：剥 # 后加 >', () {
      expect(applyBlockPrefix('## x', BlockType.blockquote), '> x');
    });

    test('已是 blockquote 的行不叠加前缀（幂等）', () {
      expect(
        applyBlockPrefix('> a\n> b', BlockType.blockquote),
        '> a\n> b',
      );
    });

    test('空字符串产生单个 > 前缀', () {
      expect(applyBlockPrefix('', BlockType.blockquote), '> ');
    });
  });

  group('applyBlockPrefix → heading（仅首行加 #）', () {
    test('多行 blockquote 转 heading：首行 #，其余行仅剥前缀', () {
      expect(
        applyBlockPrefix('> a\n> b', BlockType.heading),
        '# a\nb',
      );
    });

    test('已是 heading 不叠加（# 归一化为单级）', () {
      expect(applyBlockPrefix('### deep', BlockType.heading), '# deep');
    });

    test('列表项转 heading', () {
      expect(applyBlockPrefix('- item', BlockType.heading), '# item');
    });
  });

  group('applyBlockPrefix → 其他类型（等价 paragraph）', () {
    test('code 目标仅去前缀', () {
      expect(applyBlockPrefix('> quoted', BlockType.code), 'quoted');
    });
  });
}
