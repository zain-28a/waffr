package com.waffr.app

import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * The "waffr/pbkdf2" method channel. Derivations run on one background thread
 * (never the main thread, so no ANR); replies go back on the main looper.
 * Inputs and outputs are never logged.
 */
class Pbkdf2Channel(private val context: Context, messenger: BinaryMessenger) {
    private val worker: ExecutorService = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "waffr-pbkdf2").apply { isDaemon = true }
    }
    private val main = Handler(Looper.getMainLooper())

    init {
        MethodChannel(messenger, "waffr/pbkdf2").setMethodCallHandler { call, result ->
            when (call.method) {
                "derive" -> derive(call, result, factory = false)
                "deriveWithFactory" -> derive(call, result, factory = true)
                "info" -> result.success(info())
                else -> result.notImplemented()
            }
        }
    }

    private fun derive(call: MethodCall, result: MethodChannel.Result, factory: Boolean) {
        val password = call.argument<ByteArray>("password")
        val salt = call.argument<ByteArray>("salt")
        val iterations = call.argument<Number>("iterations")?.toInt()
        val length = call.argument<Number>("length")?.toInt()
        if (password == null || salt == null || iterations == null || length == null) {
            result.error("bad_arguments", "pbkdf2 arguments", null)
            return
        }
        worker.execute {
            try {
                val derived = if (factory) {
                    Pbkdf2.secretKeyFactory(password, salt, iterations, length)
                } else {
                    Pbkdf2.hmacSha256(password, salt, iterations, length)
                }
                main.post { result.success(derived) }
            } catch (error: Exception) {
                main.post { result.error("pbkdf2_failed", error.javaClass.simpleName, null) }
            } finally {
                password.fill(0)
            }
        }
    }

    private fun info(): Map<String, Any?> {
        val version = try {
            val info = context.packageManager.getPackageInfo(context.packageName, 0)
            "${info.versionName}+${if (Build.VERSION.SDK_INT >= 28) info.longVersionCode else @Suppress("DEPRECATION") info.versionCode.toLong()}"
        } catch (error: Exception) {
            "?"
        }
        return mapOf(
            "platform" to "android",
            "implementation" to "javax.crypto.Mac HmacSHA256 (${javax.crypto.Mac.getInstance("HmacSHA256").provider.name})",
            "manufacturer" to Build.MANUFACTURER,
            "model" to Build.MODEL,
            "soc" to if (Build.VERSION.SDK_INT >= 31) "${Build.SOC_MANUFACTURER} ${Build.SOC_MODEL}" else Build.HARDWARE,
            "abis" to Build.SUPPORTED_ABIS.joinToString(","),
            "os_version" to Build.VERSION.RELEASE,
            "sdk" to Build.VERSION.SDK_INT,
            "app_version" to version,
            "cpu_count" to Runtime.getRuntime().availableProcessors(),
            "package" to context.packageName,
        )
    }
}
