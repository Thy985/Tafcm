package com.formulafix.formula_fix

import android.content.Intent
import android.net.Uri
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

/**
 * P0 修复（2026-08-04）：支持从外部应用（微信/QQ/浏览器等）通过 ACTION_VIEW
 * 打开 .md 文件。应用愿景第 4 条："任意来源 .md 文件即开即看"。
 *
 * 工作流程：
 * 1. 系统因 [AndroidManifest.xml] 中的 VIEW intent-filter 启动本 Activity
 *    （或调用 onNewIntent，若应用已在后台）。
 * 2. [MainActivity] 提取 Intent.data（content:// 或 file:// URI），
 *    通过 [MethodChannel] 传递给 Flutter 层（key = "external_file_uri"）。
 * 3. Flutter 层通过反向 [MethodChannel] 调用 [readUriBytes] 读取字节流
 *    （content:// URI 不能用 dart:io 的 File() 直接读，必须经 ContentResolver）。
 * 4. Flutter 层用 [decodeBytesAuto] 解码（兼容 GBK / UTF-8 BOM 等），
 *    走正常 [EditorPage._loadFromFile] 流程。
 *
 * 关键：不能在 Kotlin 层直接读字节传给 Flutter（一次性 ByteArray 可能很大，
 * 且 MethodChannel 二进制通道对大对象效率低）。改为"按需读取"——
 * Flutter 拿到 URI 字符串后，调用 readUriBytes 一次读完全部字节。
 *
 * 缓存：[pendingUri] 在 Flutter 层尚未注册 MethodChannel 时缓存最近一次 URI。
 *
 * **冷启动时序**（重要）：
 * - onCreate → handleViewIntent（channel 为 null → 缓存到 pendingUri）
 * - configureFlutterEngine（注册 Kotlin 侧 handler，但 Flutter 侧 main() 尚未运行）
 * - main() 运行 → ExternalFileService.initialize() → 调用 getInitialUri 取回 pendingUri
 * - 注意：configureFlutterEngine 里**不能**直接 invokeMethod 推给 Flutter，
 *   因为此时 Flutter 侧 handler 未注册，消息会被丢弃。
 *
 * **热启动时序**（应用已在后台）：
 * - onNewIntent → handleViewIntent（channel 已存在 → 立即 invokeMethod 推给 Flutter）
 */
class MainActivity : FlutterActivity() {

    companion object {
        private const val TAG = "FormulaFix/Main"
        private const val CHANNEL = "formulafix.app/external_file"
        private const val METHOD_READ_BYTES = "readUriBytes"
        private const val METHOD_INITIAL_URI = "initialUri"
        private const val METHOD_GET_INITIAL_URI = "getInitialUri"
    }

    /** 待传递给 Flutter 的外部 URI（冷启动时 Flutter 还未注册 MethodChannel）。 */
    private var pendingUri: String? = null

    /** MethodChannel 实例，configureFlutterEngine 后非空。 */
    private var channel: MethodChannel? = null

    /**
     * 禁用 Flutter 默认 deep linking 行为（冷启动路径）。
     *
     * FlutterActivity 默认会把 ACTION_VIEW Intent 的 data URI 作为初始路由
     * 传给 Flutter（"deep linking"），导致 GoRouter 收到 `file:///xxx.md`
     * 作为 location → "no routes for location" 错误。
     *
     * 我们通过 [handleViewIntent] + MethodChannel 自己处理外部 URI，不需要
     * Flutter 的默认 deep linking。强制初始路由为 `/`，由 BootstrapScreen
     * 读取 [ExternalFileService.initialUri] 决定跳转目标。
     */
    override fun getInitialRoute(): String? = "/"

    /**
     * 禁用 Flutter 默认 deep linking 行为（热启动路径，代码级保险）。
     *
     * **根因**：FlutterActivityAndFragmentDelegate.onNewIntent 会调用
     * `maybeGetInitialRouteFromIntent(intent)`，该方法在 `shouldHandleDeeplinking()`
     * 返回 true 时把 `intent.data.toString()` 通过 `navigationChannel.pushRouteInformation`
     * 推给 Flutter → GoRouter 收到 `content://c2c/opendata/...md?...` 作为 location
     * → `GoException: no routes for location: /c2c/opendata/...md?...`。
     *
     * `deepLinkEnabled` 默认返回 true（即使 manifest 无 meta-data），所以必须
     * 显式禁用。本方法是代码级保险，与 AndroidManifest 中
     * `flutter_deeplinking_enabled=false` meta-data 双重防护。
     */
    override fun shouldHandleDeeplinking(): Boolean = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    METHOD_READ_BYTES -> {
                        val uriStr = call.argument<String>("uri")
                        if (uriStr == null) {
                            result.error("invalid_arg", "uri is null", null)
                            return@setMethodCallHandler
                        }
                        try {
                            val bytes = readUriBytes(Uri.parse(uriStr))
                            result.success(bytes)
                        } catch (e: Exception) {
                            Log.e(TAG, "readUriBytes failed: ${e.message}")
                            result.error("read_failed", e.message, null)
                        }
                    }
                    // Flutter 侧启动时主动查询冷启动缓存的 URI。
                    // 冷启动时序：onCreate → handleViewIntent（channel 为 null，缓存到 pendingUri）
                    //   → configureFlutterEngine（此处注册 handler，但 Flutter 侧 main() 尚未运行，
                    //   setMethodCallHandler 还未注册）→ main() 运行 → ExternalFileService.initialize()
                    //   → 调用 getInitialUri 取回 pendingUri。
                    // 注意：不能在 configureFlutterEngine 里直接 invokeMethod 推给 Flutter，
                    // 因为此时 Flutter 侧 handler 未注册，消息会被丢弃。
                    METHOD_GET_INITIAL_URI -> {
                        result.success(pendingUri)
                        pendingUri = null
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        // 应用在后台时，系统通过 onNewIntent 传递新的 VIEW Intent。
        // 必须调 setIntent，否则 getIntent() 仍返回旧 Intent。
        setIntent(intent)
        // 热启动：Flutter 侧 handler 已注册，直接 invokeMethod 推过去。
        handleViewIntent(intent, isColdStart = false)
    }

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        // 冷启动：系统直接用 VIEW Intent 启动 Activity，Intent 在 onCreate 时可读。
        // 注意：super.onCreate 内部已调用 configureFlutterEngine，channel 已创建，
        // 但 Flutter 侧 main() 还没运行 → setMethodCallHandler 还未注册。
        // 此时若 invokeMethod 推送，消息会被丢弃。所以走 isColdStart=true 分支
        // 缓存到 pendingUri，等 Flutter 侧主动调用 getInitialUri 取回。
        handleViewIntent(intent, isColdStart = true)
    }

    /** 检查 Intent 是否为 ACTION_VIEW + .md，若是则提取 URI 传给 Flutter。 */
    private fun handleViewIntent(intent: Intent?, isColdStart: Boolean) {
        if (intent == null || intent.action != Intent.ACTION_VIEW) return

        val uri = intent.data ?: return
        val uriStr = uri.toString()
        Log.i(TAG, "Received ACTION_VIEW with URI: $uriStr (scheme=${uri.scheme}, coldStart=$isColdStart)")

        if (isColdStart) {
            // 冷启动：Flutter 侧 handler 未注册，缓存到 pendingUri。
            // Flutter 侧 main() 运行后通过 getInitialUri 主动查询取回。
            pendingUri = uriStr
        } else {
            // 热启动：Flutter 侧 handler 已注册，直接推过去。
            channel?.invokeMethod(METHOD_INITIAL_URI, uriStr)
        }
    }

    /**
     * 通过 [ContentResolver] 读取 URI 字节流。
     *
     * content:// URI（微信/QQ 等通过 SAF 传递）：走 ContentResolver.openInputStream。
     * file:// URI（旧式）：ContentResolver 同样支持，统一走此路径。
     *
     * 一次性读完到 ByteArray。.md 文件通常 < 1MB，无内存压力。
     * 若未来需要支持超大文件，再改为流式传输（但目前编辑器也是全量加载）。
     */
    private fun readUriBytes(uri: Uri): ByteArray {
        val resolver = contentResolver
        val input = resolver.openInputStream(uri)
            ?: throw IllegalStateException("openInputStream returned null for $uri")
        input.use { stream ->
            val buffer = ByteArrayOutputStream(stream.available().coerceAtLeast(8192))
            val buf = ByteArray(8192)
            while (true) {
                val n = stream.read(buf)
                if (n <= 0) break
                buffer.write(buf, 0, n)
            }
            return buffer.toByteArray()
        }
    }
}
