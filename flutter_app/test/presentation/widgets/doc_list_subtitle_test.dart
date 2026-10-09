/// issue #333-C 同名消歧副标题 helper — 纯函数单测。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:tafcm/data/models/document.dart';
import 'package:tafcm/presentation/widgets/doc_list_subtitle.dart';

Document _doc(String id, String title, DateTime createdAt) => Document(
      id: id,
      title: title,
      content: 'content-$id',
      createdAt: createdAt,
      updatedAt: createdAt,
    );

void main() {
  group('#333-C hasTitleCollision', () {
    test('列表内存在同名其它文档 → true', () {
      final a = _doc('a', '未命名文档', DateTime(2026, 10, 4, 9, 30));
      final b = _doc('b', '未命名文档', DateTime(2026, 10, 4, 10, 0));
      expect(hasTitleCollision(a, [a, b]), isTrue);
      expect(hasTitleCollision(b, [a, b]), isTrue);
    });

    test('列表内无同名其它文档 → false', () {
      final a = _doc('a', '标题甲', DateTime(2026, 10, 4));
      final b = _doc('b', '标题乙', DateTime(2026, 10, 5));
      expect(hasTitleCollision(a, [a, b]), isFalse);
    });

    test('单元素列表 → false（自身不算碰撞）', () {
      final a = _doc('a', '标题', DateTime(2026, 10, 4));
      expect(hasTitleCollision(a, [a]), isFalse);
    });
  });

  group('#333-C formatDateTimeShort', () {
    test('补零格式化 yyyy-MM-dd HH:mm', () {
      expect(formatDateTimeShort(DateTime(2026, 10, 4, 9, 5)),
          '2026-10-04 09:05');
    });
  });

  group('#333-C disambiguatedSubtitle', () {
    test('同名碰撞 → 副标题前缀创建时间', () {
      final a = _doc('a', '同名', DateTime(2026, 10, 4, 9, 0));
      final b = _doc('b', '同名', DateTime(2026, 10, 5, 8, 30));
      expect(disambiguatedSubtitle(a, [a, b], '预览'),
          '2026-10-04 09:00 · 预览');
    });

    test('无碰撞 → 原样返回（golden 不变的前提）', () {
      final a = _doc('a', '标题', DateTime(2026, 10, 4));
      final b = _doc('b', '另一篇', DateTime(2026, 10, 5));
      expect(disambiguatedSubtitle(a, [a, b], '预览'), '预览');
    });

    test('同名但传入自身列表 → 不触发（与列表比较而非全局）', () {
      final a = _doc('a', '同名', DateTime(2026, 10, 4));
      expect(disambiguatedSubtitle(a, [a], '预览'), '预览');
    });
  });
}