/// #319 文档文件消失守护：resume 时校验活动文档落盘文件仍在，消失则从内存重建。
///
/// **事件背景**（QA 2026-10-04 实测）：活动文档 .md 被外部删除后，应用不
/// 重建、不告知——[AutosaveService] 仅由 dirty 翻转驱动，用户停止编辑就
/// 再无保存时机，磁盘长期无文件而 UI 毫无提示；应用退出后内存内容丢失，
/// 文件页只剩标题。resume 是最佳检测点：文件消失多发生在此前离开应用期间
/// （外部文件管理器 / 清理工具 / 同步冲突），一次 stat 即可覆盖。
///
/// **拆分理由**：EditorPage 已贴近 400 行架构上限（TC-ARCH-7），且真实
/// 文件 I/O 在 widget 测试的 fake-async 区内无法推进——守护逻辑独立成纯
/// 函数后可用普通 `test()` + 临时目录覆盖（doc_file_resume_guard_test），
/// EditorPage 只保留接线（observer + SnackBar）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/document_repository.dart';
import '../../providers/editor_providers.dart';
import '../../providers/file_repository_provider.dart';

/// 轻量生命周期观察者：仅转发 resume 事件（#319）。
///
/// EditorPage 无需混入 [WidgetsBindingObserver]（节省行数且职责单一）。
class ResumeGuardObserver with WidgetsBindingObserver {
  final VoidCallback onResume;

  ResumeGuardObserver(this.onResume);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) onResume();
  }
}

/// 文档 .md 文件当前是否存在于磁盘（O(1) stat，不读全文）。
///
/// 存在性检查走仓库端口（TC-ARCH-1：presentation 禁止直连 [File]）。
Future<bool> docFileExists(DocumentRepository repo, String path) =>
    repo.documentFileExists(path);

/// resume 守护：发现落盘文件消失则从内存重建，返回是否执行了重建。
///
/// - `path == null`（演示文档 / 外部 URI 无落盘主）→ 不守护，返回 false；
/// - 文件健在 → 不动文件，返回 false；
/// - 文件消失 → `writeDocument` 用内存内容重建，返回 true；
/// - 仓储异常 → 经 observability 上报（`DocFileRecreateError`）后吞掉，
///   返回 false（守护失败不崩溃，下次 resume 重试）。
Future<bool> guardAndReportDocFileOnResume({
  required WidgetRef ref,
  required String? path,
  required String title,
  required String content,
}) async {
  if (path == null) return false; // 演示 / 外部 URI 文档无落盘主，无需守护
  final observability = ref.read(observabilityProvider);
  try {
    final recreated = await recreateDocFileIfMissing(
      repo: ref.read(fileRepositoryProvider),
      path: path,
      title: title,
      content: content,
    );
    if (recreated) {
      observability.captureError(
        type: 'DocFileMissingRecreated',
        message: 'document file missing on resume, recreated from memory',
        commandName: 'guardAndReportDocFileOnResume',
        commandParams: {'path': path},
      );
    }
    return recreated;
  } catch (e) {
    debugPrint('[EditorPage] recreate missing doc failed: $e');
    observability.captureError(
      type: 'DocFileRecreateError',
      message: '$e',
      commandName: 'guardAndReportDocFileOnResume',
      commandParams: {'path': path},
    );
    return false;
  }
}

/// 守护本体：文件消失则用内存内容重建，返回是否执行了重建。
///
/// 独立于上报与 UI（单一职责）；仓储异常原样上抛（由调用方决定上报）。
Future<bool> recreateDocFileIfMissing({
  required DocumentRepository repo,
  required String path,
  required String title,
  required String content,
}) async {
  if (await repo.documentFileExists(path)) return false;
  await repo.writeDocument(path, title: title, content: content);
  return true;
}

/// #319：检测到活动文档文件从磁盘消失后已从内存重建的 SnackBar 反馈。
///
/// 与 `showFileLoadFailureSnackBar` 同风格：不展示 stack / detail
/// （AGENTS.md §4.4），只告知发生了什么与当前状态。
void showDocFileRecreatedSnackBar(BuildContext context) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: const Text('检测到文档文件已从磁盘消失，已从内存重建。\n'
          '建议尽快返回首页确认文档列表正常。'),
      duration: const Duration(seconds: 5),
      action: SnackBarAction(
        label: '知道了',
        onPressed: () {},
      ),
    ),
  );
}
