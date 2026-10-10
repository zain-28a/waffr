package com.waffr.app

import android.content.ClipData
import android.content.Intent
import android.content.pm.PackageManager
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class SharedPdfProvider : FileProvider()

class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "waffer/share_pdf",
        ).setMethodCallHandler { call, result ->
            if (call.method != "share") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val path = call.argument<String>("path")
            if (path.isNullOrBlank()) {
                result.error("bad_path", "Missing PDF path", null)
                return@setMethodCallHandler
            }
            try {
                sharePdf(path)
                result.success(null)
            } catch (error: Exception) {
                result.error("share_failed", error.message, null)
            }
        }
    }

    private fun sharePdf(path: String) {
        val file = File(path)
        if (!file.exists() || file.length() <= 0L) {
            throw IllegalStateException("PDF file is missing")
        }
        val authority = "$packageName.shared_pdfs"
        val uri = FileProvider.getUriForFile(this, authority, file)
        val send = Intent(Intent.ACTION_SEND).apply {
            type = "application/pdf"
            putExtra(Intent.EXTRA_STREAM, uri)
            putExtra(Intent.EXTRA_TITLE, "waffer-expenses.pdf")
            clipData = ClipData.newRawUri("waffer-expenses.pdf", uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        val targets = packageManager.queryIntentActivities(
            send,
            PackageManager.MATCH_DEFAULT_ONLY,
        )
        for (info in targets) {
            grantUriPermission(
                info.activityInfo.packageName,
                uri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION,
            )
        }
        val chooser = Intent.createChooser(send, "مشاركة السجل").apply {
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        startActivity(chooser)
    }
}
