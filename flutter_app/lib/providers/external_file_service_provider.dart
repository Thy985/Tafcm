/// 外部文件服务 Provider（presentation 安全入口，AGENTS.md §4.2）。
///
/// [EditorPage] 等表现层组件通过本 Provider 访问 [ExternalFileService]，
/// 避免直接 import `core/services/external_file_service.dart`（TC-ARCH-3 守门）。
///
/// [ExternalFileService] 是单例（[ExternalFileService.instance]），
/// 在 main() 中通过 `await initialize()` 完成初始化。
/// Provider 仅暴露实例引用，不负责生命周期管理。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/services/external_file_service.dart';

export '../core/services/external_file_service.dart' show ExternalFileService;

/// 暴露 [ExternalFileService] 单例给 presentation 层。
///
/// 使用方式：
/// ```dart
/// final service = ref.read(externalFileServiceProvider);
/// final content = await service.readContent(uri);
/// ```
final externalFileServiceProvider = Provider<ExternalFileService>((ref) {
  return ExternalFileService.instance;
});
