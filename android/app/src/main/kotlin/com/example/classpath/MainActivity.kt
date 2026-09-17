package com.dahedan.classpath

import android.content.ClipData
import android.content.Intent
import android.net.Uri
import android.provider.Settings
import android.util.Base64
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "classpath/share"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // 是否安装了可接收分享的目标应用（微信 / QQ）。
                    "canShareTo" -> {
                        val pkg = call.argument<String>("package")
                        result.success(pkg != null && resolveShareTarget(pkg))
                    }
                    // 把内存文件（json / 图片）直接分享给指定应用。
                    "shareFileTo" -> {
                        val pkg = call.argument<String>("package")
                        val mime = call.argument<String>("mimeType") ?: "application/octet-stream"
                        val fileName = call.argument<String>("fileName")
                        val bytesBase64 = call.argument<String>("bytesBase64")
                        if (pkg == null || fileName == null || bytesBase64 == null) {
                            result.error("bad_args", "missing arguments", null)
                            return@setMethodCallHandler
                        }
                        result.success(shareFileTo(pkg, mime, fileName, bytesBase64))
                    }
                    // 打开应用信息页（用户在那里点「通知」进入完整通知设置）。
                    // 直接从 ACTION_APP_NOTIFICATION_SETTINGS 进入时，部分 ROM
                    // 只渲染通知总开关+类别，缺横幅/锁屏/声音等开关，
                    // 因此改从应用信息页进入，与系统设置路径完全一致。
                    "openNotificationSettings" -> {
                        openNotificationSettings()
                        result.success(true)
                    }
                    // 调起系统分享面板（不带 createChooser）：交回 ROM 自己的
                    // 分享面板渲染图标/分组，避免出现 AOSP 那个传统方形图标列表。
                    "shareToSystem" -> {
                        val mime = call.argument<String>("mimeType")
                            ?: "application/octet-stream"
                        val fileName = call.argument<String>("fileName")
                        val bytesBase64 = call.argument<String>("bytesBase64")
                        if (fileName == null || bytesBase64 == null) {
                            result.error("bad_args", "missing arguments", null)
                            return@setMethodCallHandler
                        }
                        result.success(shareToSystem(mime, fileName, bytesBase64))
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun resolveShareTarget(packageName: String): Boolean =
        try {
            val intent = Intent(Intent.ACTION_SEND).apply {
                type = "text/plain"
                setPackage(packageName)
            }
            intent.resolveActivity(packageManager) != null
        } catch (_: Exception) {
            false
        }

    private fun openNotificationSettings() {
        // 主路径：应用信息页，与「系统设置 → 应用 → 课途」一致，
        // 再点「通知」即可看到完整的开关（横幅/锁屏/声音/类别）。
        try {
            val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                data = Uri.parse("package:${applicationContext.packageName}")
            }
            startActivity(intent)
        } catch (_: Exception) {
            // 个别机型不支持应用信息页时，退回通知设置页。
            try {
                val intent = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
                    putExtra(Settings.EXTRA_APP_PACKAGE, applicationContext.packageName)
                }
                startActivity(intent)
            } catch (_: Exception) {}
        }
    }

    private fun shareFileTo(
        packageName: String,
        mimeType: String,
        fileName: String,
        bytesBase64: String,
    ): Boolean =
        try {
            val bytes = Base64.decode(bytesBase64, Base64.DEFAULT)
            val tmp = File(cacheDir, "share_$fileName")
            tmp.writeBytes(bytes)
            val uri =
                FileProvider.getUriForFile(
                    this,
                    "${applicationContext.packageName}.fileprovider",
                    tmp,
                )
            val intent = Intent(Intent.ACTION_SEND).apply {
                type = mimeType
                putExtra(Intent.EXTRA_STREAM, uri)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                setPackage(packageName)
            }
            startActivity(intent)
            true
        } catch (_: Exception) {
            false
        }

    /// 调起系统分享面板。
    ///
    /// 注意：这里**不能**用 Intent.createChooser —— 那会让系统弹出 AOSP 自带的
    /// 传统选择器（方形图标列表）；直接 startActivity(ACTION_SEND) 才会交回
    /// 各 ROM 自己的分享面板（如华为的圆角图标 + 分页样式）。
    /// clipData 保证被选中的应用拿到读取权限（Android 11+ 推荐做法）。
    private fun shareToSystem(
        mimeType: String,
        fileName: String,
        bytesBase64: String,
    ): Boolean =
        try {
            val bytes = Base64.decode(bytesBase64, Base64.DEFAULT)
            val tmp = File(cacheDir, "share_$fileName")
            tmp.writeBytes(bytes)
            val uri =
                FileProvider.getUriForFile(
                    this,
                    "${applicationContext.packageName}.fileprovider",
                    tmp,
                )
            val intent = Intent(Intent.ACTION_SEND).apply {
                type = mimeType
                putExtra(Intent.EXTRA_STREAM, uri)
                clipData = ClipData.newRawUri(null, uri)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            startActivity(intent)
            true
        } catch (_: Exception) {
            false
        }
}
