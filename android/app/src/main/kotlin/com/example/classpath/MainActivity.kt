package com.example.classpath

import android.content.Intent
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
}
