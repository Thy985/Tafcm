/// TC-1.2.8: 原子写无 .tmp 残留
///
/// 对应 ADR-0003、AGENTS.md §4.1。
/// 业务价值：进程崩溃 / 写入中断时不能留下半截 .md。
library;

import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:formula_fix/core/services/file_repository.dart';

void main() {
  group('TC-1.2.8 原子写无 .tmp 残留', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('atomic_write_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('正常写入：写入完成后无 .tmp 残留', () async {
      final file = File('${tempDir.path}${Platform.pathSeparator}doc.md');
      await atomicWrite(file, '# 测试\n\n内容');
      expect(await file.exists(), isTrue);
      expect(await File('${file.path}.tmp').exists(), isFalse,
          reason: '正常写入后 .tmp 必须已被 rename');
    });

    test('100 次连续写入：无 .tmp 残留', () async {
      final file = File('${tempDir.path}${Platform.pathSeparator}stress.md');
      for (var i = 0; i < 100; i++) {
        await atomicWrite(file, '版本 $i\n');
      }
      expect(await file.exists(), isTrue);
      expect(await File('${file.path}.tmp').exists(), isFalse);
    });

    test('覆盖写入：旧内容被替换，无 .tmp 残留', () async {
      final file = File('${tempDir.path}${Platform.pathSeparator}overwrite.md');
      await atomicWrite(file, '版本 1');
      await atomicWrite(file, '版本 2');
      expect(await file.readAsString(), '版本 2');
      expect(await File('${file.path}.tmp').exists(), isFalse);
    });

    test('目录不存在时自动创建', () async {
      final nested = '${tempDir.path}${Platform.pathSeparator}nested${Platform.pathSeparator}deep';
      final file = File('$nested${Platform.pathSeparator}doc.md');
      await atomicWrite(file, '内容');
      expect(await file.exists(), isTrue);
    });
  });

  group('原子写抗外部干扰（.tmp 在 rename 前被删）', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('atomic_write_retry_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('单次干扰：自动重试后写入成功', () async {
      final file = File('${tempDir.path}${Platform.pathSeparator}flaky.md');
      final tmpPath = '${file.path}.tmp';
      final flakyTmp = _FlakyRenameFile(File(tmpPath), failures: 1);

      await IOOverrides.runZoned(
        () async => atomicWrite(file, '重试后的内容'),
        createFile: (path) => path == tmpPath ? flakyTmp : file,
      );

      expect(flakyTmp.renameAttempts, 2, reason: '首次 rename 失败后应重试一次');
      expect(await file.readAsString(), '重试后的内容');
      expect(await File(tmpPath).exists(), isFalse);
    });

    test('持续干扰：超过重试上限后抛 FileSystemException 且不留 .tmp', () async {
      final file = File('${tempDir.path}${Platform.pathSeparator}hostile.md');
      final tmpPath = '${file.path}.tmp';
      final flakyTmp = _FlakyRenameFile(
        File(tmpPath),
        failures: kAtomicWriteMaxAttempts,
      );

      await expectLater(
        IOOverrides.runZoned(
          () async => atomicWrite(file, '内容'),
          createFile: (path) => path == tmpPath ? flakyTmp : file,
        ),
        throwsA(isA<FileSystemException>()),
      );

      expect(flakyTmp.renameAttempts, kAtomicWriteMaxAttempts,
          reason: '应恰好尝试 kAtomicWriteMaxAttempts 次');
      expect(await File(tmpPath).exists(), isFalse, reason: '失败后不得留下 .tmp');
      expect(await file.exists(), isFalse);
    });

    test('非文件系统异常不重试，立即上抛', () async {
      final file = File('${tempDir.path}${Platform.pathSeparator}fatal.md');
      final tmpPath = '${file.path}.tmp';
      final failing = _FatalWriteFile(File(tmpPath));

      await expectLater(
        IOOverrides.runZoned(
          () async => atomicWrite(file, '内容'),
          createFile: (path) => path == tmpPath ? failing : file,
        ),
        throwsA(isA<StateError>()),
      );

      expect(failing.writeAttempts, 1, reason: '非 FileSystemException 不得重试');
    });
  });
}

/// 模拟「外部清理器在 rename 前删掉 `.tmp`」：
/// 前 [failures] 次 `rename` 先删掉 tmp 再抛 [FileSystemException]。
class _FlakyRenameFile implements File {
  _FlakyRenameFile(this._inner, {required int failures})
      : _remainingFailures = failures;

  final File _inner;
  int _remainingFailures;

  /// `rename` 被调用的总次数（含失败）。
  int renameAttempts = 0;

  @override
  String get path => _inner.path;

  @override
  Directory get parent => _inner.parent;

  @override
  Future<bool> exists() => _inner.exists();

  @override
  Future<FileSystemEntity> delete({bool recursive = false}) =>
      _inner.delete(recursive: recursive);

  @override
  Future<File> writeAsString(
    String contents, {
    FileMode mode = FileMode.write,
    Encoding encoding = utf8,
    bool flush = false,
  }) =>
      _inner.writeAsString(contents,
          mode: mode, encoding: encoding, flush: flush);

  @override
  Future<File> rename(String newPath) async {
    renameAttempts++;
    if (_remainingFailures > 0) {
      _remainingFailures--;
      if (await _inner.exists()) await _inner.delete();
      throw const FileSystemException(
        '模拟外部清理器在 rename 前删除 .tmp',
        '',
        OSError('No such file or directory', 2),
      );
    }
    return _inner.rename(newPath);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

/// 写入时抛非文件系统异常，用于验证「不可恢复错误不重试」。
class _FatalWriteFile implements File {
  _FatalWriteFile(this._inner);

  final File _inner;

  /// `writeAsString` 被调用的总次数。
  int writeAttempts = 0;

  @override
  String get path => _inner.path;

  @override
  Directory get parent => _inner.parent;

  @override
  Future<bool> exists() => _inner.exists();

  @override
  Future<FileSystemEntity> delete({bool recursive = false}) =>
      _inner.delete(recursive: recursive);

  @override
  Future<File> writeAsString(
    String contents, {
    FileMode mode = FileMode.write,
    Encoding encoding = utf8,
    bool flush = false,
  }) async {
    writeAttempts++;
    throw StateError('不可恢复的编码错误');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}
