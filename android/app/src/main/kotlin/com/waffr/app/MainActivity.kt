package com.waffr.app

import android.content.ClipData
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class SharedPdfProvider : FileProvider()

class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        Pbkdf2Channel(applicationContext, flutterEngine.dartExecutor.binaryMessenger)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "waffr/haptics",
        ).setMethodCallHandler { call, result ->
            if (call.method != "play") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            try {
                playHaptic(call.arguments as? String ?: "click")
                result.success(null)
            } catch (error: Exception) {
                result.error("haptic_failed", error.message, null)
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "waffr/share_pdf",
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

    /**
     * Plays a short touch effect on the vibrator itself. View haptics are
     * silent on many phones unless a system setting is on, so the app drives
     * the motor directly and offers its own switch in settings.
     */
    @Suppress("DEPRECATION")
    private fun playHaptic(kind: String) {
        val found: Vibrator? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            (getSystemService(VIBRATOR_MANAGER_SERVICE) as? VibratorManager)?.defaultVibrator
        } else {
            getSystemService(VIBRATOR_SERVICE) as? Vibrator
        }
        val vibrator = found ?: return
        if (!vibrator.hasVibrator()) return

        // Length in milliseconds and strength (1..255) where the phone has
        // no ready-made effect.
        val (millis, strength) = when (kind) {
            "tick" -> 8L to 70
            "click" -> 14L to 140
            "heavy" -> 24L to 255
            else -> 14L to 140
        }
        when {
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q -> {
                val effect = when (kind) {
                    "tick" -> VibrationEffect.EFFECT_TICK
                    "heavy" -> VibrationEffect.EFFECT_HEAVY_CLICK
                    "double" -> VibrationEffect.EFFECT_DOUBLE_CLICK
                    else -> VibrationEffect.EFFECT_CLICK
                }
                vibrator.vibrate(VibrationEffect.createPredefined(effect))
            }
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.O -> {
                val amplitude = if (vibrator.hasAmplitudeControl()) {
                    strength
                } else {
                    VibrationEffect.DEFAULT_AMPLITUDE
                }
                vibrator.vibrate(VibrationEffect.createOneShot(millis, amplitude))
            }
            else -> vibrator.vibrate(millis)
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
            putExtra(Intent.EXTRA_TITLE, "waffr-expenses.pdf")
            clipData = ClipData.newRawUri("waffr-expenses.pdf", uri)
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
