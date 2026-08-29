/// 外部文件入口服务（Android ACTION_VIEW Intent 桥接）。
///
/// 监听 [MethodChannel]("tafcm.app/external_file")，接收从
/// [MainActivity] 传递过来的外部 URI（content:// 或 file://）。
///
/// 当用户在微信 / QQ / 浏览器等第三方应用选择 .md 文件 → "其他应用打开"
/// → 系统通过 ACTION_VIEW 启动本应用，[MainActivity] 提取 Intent.data
/// URI 通过 MethodChannel 推到本服务。
///
/// 本服务持有 Stream<String>（URI 字符串），路由层（[appRouter] /
/// BootstrapScreen）监听该 Stream，在收到 URI 时：
/// 1. 通过 [readUriBytes] 反向调用 [MainActivity.readUriBytes] 读取字节流
///    （content:// URI 不能用 dart:io 的 File() 直接读）
/// 2. 用 [decodeBytesAuto] 解码（兼容 GBK / UTF-8 BOM）
/// 3. 导航到 /editor?externalUri=<encoded>
///
/// 设计权衡：
/// - 不在本 service 内直接读字节 → 字节流读取由 EditorPage 触发（按需），
///   避免应用启动时立刻读大文件导致首帧卡顿。
/// - URI 以字符串形式在 Stream 中传递 → MethodChannel 二进制通道效率高。
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'file_service.dart' show decodeBytesAuto;

/// 与 [MainActivity.kt] 配套的 MethodChannel 名。
const _kChannelName = 'tafcm.app/external_file';

/// 单例服务：监听外部应用通过 ACTION_VIEW 传来的 .md 文件 URI。
///
/// 使用流程：
/// 1. App 启动时 await [ExternalFileService.instance.initialize] 注册监听 +
///    主动查询冷启动缓存的 URI（[getInitialUri]）。
/// 2. [BootstrapScreen] 同步检查 [initialUri]，若非空直接跳 /editor?externalUri=...
/// 3. [TafcmApp] 订阅 [uriStream]，热启动时（onNewIntent）收到 URI 后跳转。
/// 4. [EditorPage] 收到 externalUri 参数时调用 [readBytes] 读字节并加载。
class ExternalFileService {
  ExternalFileService._();
  static final ExternalFileService instance = ExternalFileService._();

  final MethodChannel _channel = const MethodChannel(_kChannelName);
  final StreamController<String> _uriController =
      StreamController<String>.broadcast();

  /// 是否已调用 [initialize]（防止重复注册 Handler）。
  bool _initialized = false;

  /// 冷启动时从原生侧 [getInitialUri] 取回的 URI（可能为 null）。
  ///
  /// 由 [initialize] 一次性填充。[BootstrapScreen] 同步读取此字段决定是否
  /// 跳过 SharedPreferences 启动屏，直接进入 /editor?externalUri=...
  String? _initialUri;

  /// 暴露给路由层的 URI Stream。每次收到外部 URI 时推送。
  ///
  /// 冷启动 URI 也会推送到此 Stream（[initialize] 内推送一次）。
  /// 热启动（onNewIntent）每次推送一次。
  Stream<String> get uriStream => _uriController.stream;

  /// 冷启动时缓存的 URI（同步读取，供 [BootstrapScreen] 使用）。
  ///
  /// 必须在 [initialize] 完成后才有效。null 表示无冷启动外部 URI。
  String? get initialUri => _initialUri;

  /// 注册 MethodChannel Handler 并查询冷启动 URI。应在 main() 中调用一次。
  ///
  /// 幂等：重复调用无副作用（但不会重新查询 initialUri）。
  ///
  /// 必须用 await 等待完成，否则 [initialUri] 还未填充。
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'initialUri':
          // 热启动场景：MainActivity.onNewIntent 推来的外部 URI 字符串。
          final uri = call.arguments as String?;
          if (uri != null && uri.isNotEmpty) {
            debugPrint('ExternalFileService: received warm-start URI $uri');
            _uriController.add(uri);
          }
          return null;
        default:
          // 其他方法（如反向调用 readUriBytes）走 [readBytes]，不在这里处理。
          return null;
      }
    });

    // 冷启动场景：主动向原生侧查询 pendingUri。
    // 时序：MainActivity.onCreate 缓存 URI 到 pendingUri → main() 运行 →
    // 这里调用 getInitialUri 取回。若返回非空，同时推送到 stream（让
    // TafcmApp 的 uriStream 监听者也能收到，统一处理路径）。
    try {
      final uri = await _channel.invokeMethod<String>('getInitialUri');
      if (uri != null && uri.isNotEmpty) {
        debugPrint('ExternalFileService: retrieved cold-start URI $uri');
        _initialUri = uri;
        _uriController.add(uri);
      }
    } catch (e) {
      // 原生侧未实现该方法（旧版本 APK）或 channel 异常 → 忽略，按无外部 URI 处理。
      debugPrint('ExternalFileService: getInitialUri failed: $e');
    }

    debugPrint('ExternalFileService initialized');
  }

  /// 通过 MethodChannel 反向调用 [MainActivity.readUriBytes] 读取 URI 字节流。
  ///
  /// 用于 [EditorPage] 加载 externalUri 时获取文件内容。
  /// content:// URI 不能用 dart:io File() 直接读，必须经 ContentResolver。
  ///
  /// 失败时抛 [PlatformException]（被 EditorPage 的 try/catch 捕获，回退种子文档）。
  Future<Uint8List> readBytes(String uri) async {
    final result = await _channel.invokeMethod<List<int>>(
      'readUriBytes',
      <String, dynamic>{'uri': uri},
    );
    if (result == null) {
      throw PlatformException(
        code: 'read_failed',
        message: 'readUriBytes returned null for $uri',
      );
    }
    return Uint8List.fromList(result);
  }

  /// 读取 URI 字节并解码为字符串（用 [decodeBytesAuto] 兼容 GBK / UTF-8 BOM）。
  ///
  /// 供 [EditorPage._loadFromExternalUri] 一步到位使用。
  Future<String> readContent(String uri) async {
    final bytes = await readBytes(uri);
    return decodeBytesAuto(bytes);
  }

  /// 释放资源（应用退出时调用，目前未使用，保留扩展点）。
  void dispose() {
    _uriController.close();
    _channel.setMethodCallHandler(null);
    _initialized = false;
  }
}
