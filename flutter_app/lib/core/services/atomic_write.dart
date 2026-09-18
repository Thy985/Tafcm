/// 原子写文件 I/O（自 file_repository.dart 拆出，TC-ARCH-7 行数控制）。
///
/// 职责：`<path>.tmp` 落盘 → 删旧目标 → rename 的原子写，含抗外部干扰
/// 重试。String 版（`atomicWrite`）保留 writeAsString 路径——
/// `atomic_write_test` 经 `IOOverrides` 注入依赖 `File()` 构造与
/// `writeAsString`，字节版（`atomicWriteBytes`）走 writeAsBytes。
library;

import 'dart:async';
import 'dart:io';

/// [atomicWrite] 的最大重试次数（含首次）。
const int kAtomicWriteMaxAttempts = 3;

/// [atomicWrite] 重试的基础退避间隔，第 n 次重试等待 n × 该值。
const Duration kAtomicWriteRetryBackoff = Duration(milliseconds: 20);

/// 原子写：先写 `<path>.tmp`，落盘后（删除旧目标）rename 到最终路径。
///
/// 避免进程崩溃 / 写入中断时留下半截 `.md`。Windows 上 `rename`
/// 不能直接覆盖已存在文件，故先删除旧目标再 rename。
///
/// **抗外部干扰**：`.tmp` 落盘到 rename 之间存在一个时间窗，期间可能被
/// 外部进程（磁盘清理工具、杀毒软件实时扫描、同步客户端）删除或占用，
/// 导致 rename 抛 [FileSystemException]（Windows 上典型为
/// `errno = 2 / 32`）。这类故障是瞬时的，整段"写 tmp → 删旧 → rename"
/// 会最多重试 [kAtomicWriteMaxAttempts] 次、按 [kAtomicWriteRetryBackoff]
/// 线性退避。非文件系统异常（如编码错误）不重试，立即上抛。
///
/// 重试语义安全：每次尝试都重新写入完整的 [content]，
/// 不存在写入一半再续写的情况；失败路径始终清理残留 `.tmp`。
///
/// ⚠️ 权衡（delete-then-rename）：每次尝试会先删除已存在的旧目标再 rename，
/// 若 rename 持续失败并耗尽重试上限，旧内容将丢失（新内容也未落盘）。属设计固有
/// 权衡，非本处回归；该行为已由 `atomic_write_test` 固化，便于后续若改为
/// "写临时件、失败时保留旧件"时及时察觉。
Future<void> atomicWrite(File file, String content) async {
  final dir = file.parent;
  await dir.create(recursive: true);
  final tmp = File('${file.path}.tmp');

  for (var attempt = 1; attempt <= kAtomicWriteMaxAttempts; attempt++) {
    try {
      await tmp.writeAsString(content, flush: true);
      if (await file.exists()) {
        await file.delete();
      }
      await tmp.rename(file.path);
      return;
    } on FileSystemException catch (e, s) {
      await _deleteQuietly(tmp);
      if (attempt == kAtomicWriteMaxAttempts) {
        // 重试耗尽：保留原始栈上抛，便于定位外部干扰源（清理器/杀毒锁定等）。
        Error.throwWithStackTrace(e, s);
      }
      await Future<void>.delayed(kAtomicWriteRetryBackoff * attempt);
    } catch (_) {
      // 非文件系统错误不具备"重试可恢复"性质，直接上抛。
      await _deleteQuietly(tmp);
      rethrow;
    }
  }
}

/// 字节版原子写（P0-2 §4.2 写端：按 front matter 声明编码写回时，
/// 编码产物是字节而非 String，utf8 固定版无法复用）。
///
/// 重试/抗干扰语义与 [atomicWrite] 相同；tmp 写入走 `writeAsBytes`。
Future<void> atomicWriteBytes(File file, List<int> bytes) async {
  final dir = file.parent;
  await dir.create(recursive: true);
  final tmp = File('${file.path}.tmp');

  for (var attempt = 1; attempt <= kAtomicWriteMaxAttempts; attempt++) {
    try {
      await tmp.writeAsBytes(bytes, flush: true);
      if (await file.exists()) {
        await file.delete();
      }
      await tmp.rename(file.path);
      return;
    } on FileSystemException catch (e, s) {
      await _deleteQuietly(tmp);
      if (attempt == kAtomicWriteMaxAttempts) {
        Error.throwWithStackTrace(e, s);
      }
      await Future<void>.delayed(kAtomicWriteRetryBackoff * attempt);
    } catch (_) {
      await _deleteQuietly(tmp);
      rethrow;
    }
  }
}

/// 尽力删除 [file]，忽略删除过程中的任何错误（清理路径不得掩盖原始异常）。
Future<void> _deleteQuietly(File file) async {
  try {
    if (await file.exists()) await file.delete();
  } catch (_) {
    // 残留 .tmp 由下次写入覆盖，或由 recovery 流程清理。
  }
}
