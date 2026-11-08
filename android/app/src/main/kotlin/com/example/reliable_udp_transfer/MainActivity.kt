package com.example.reliable_udp_transfer

import android.app.Activity
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Environment
import android.os.PowerManager
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.view.WindowManager
import android.widget.Toast
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    private val channelName = "udp_transfer/platform"
    private val pickRequestCode = 9001
    private var pendingResult: MethodChannel.Result? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private var wifiLock: WifiManager.WifiLock? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickFile" -> {
                        pendingResult = result
                        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            type = "*/*"
                        }
                        startActivityForResult(intent, pickRequestCode)
                    }
                    "getSaveDir" -> {
                        val dir = getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS) ?: filesDir
                        if (!dir.exists()) dir.mkdirs()
                        result.success(dir.absolutePath)
                    }
                    "shareFile" -> {
                        val path = call.argument<String>("path")
                        if (path != null) {
                            saveToPublicDownloads(File(path))
                        }
                        result.success(null)
                    }
                    "setBackgroundActive" -> {
                        val active = call.argument<Boolean>("active") ?: false
                        setBackground(active)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun saveToPublicDownloads(srcFile: File) {
        if (!srcFile.exists()) return
        Thread {
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    val values = ContentValues().apply {
                        put(MediaStore.Downloads.DISPLAY_NAME, srcFile.name)
                        put(MediaStore.Downloads.IS_PENDING, 1)
                    }
                    val resolver = contentResolver
                    val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                    if (uri != null) {
                        resolver.openOutputStream(uri)?.use { out ->
                            FileInputStream(srcFile).use { input ->
                                input.copyTo(out, 64 * 1024)
                            }
                        }
                        values.clear()
                        values.put(MediaStore.Downloads.IS_PENDING, 0)
                        resolver.update(uri, values, null, null)
                    }
                }
                runOnUiThread {
                    Toast.makeText(
                        this,
                        "İndirilenler klasörüne kaydedildi: ${srcFile.name}",
                        Toast.LENGTH_LONG
                    ).show()
                }
            } catch (_: Exception) {}
        }.start()
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != pickRequestCode) return

        val res = pendingResult
        pendingResult = null
        if (resultCode != Activity.RESULT_OK || data?.data == null) {
            res?.success(null)
            return
        }

        val uri = data.data!!
        val name = resolveDisplayName(uri)
        Thread {
            try {
                val outFile = File(cacheDir, name)
                contentResolver.openInputStream(uri)?.use { input ->
                    FileOutputStream(outFile).use { output ->
                        input.copyTo(output, 64 * 1024)
                    }
                }
                runOnUiThread {
                    res?.success(mapOf("path" to outFile.absolutePath, "name" to name))
                }
            } catch (e: Exception) {
                runOnUiThread { res?.success(null) }
            }
        }.start()
    }

    private fun resolveDisplayName(uri: Uri): String {
        contentResolver.query(uri, null, null, null, null)?.use { cursor ->
            val idx = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
            if (idx >= 0 && cursor.moveToFirst()) {
                return cursor.getString(idx)
            }
        }
        return "dosya_${System.currentTimeMillis()}"
    }

    private fun setBackground(active: Boolean) {
        if (active) {
            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            if (wakeLock == null) {
                val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "udp:transfer_wake")
                wakeLock?.acquire()
            }
            if (wifiLock == null) {
                val wm = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
                @Suppress("DEPRECATION")
                wifiLock = wm.createWifiLock(WifiManager.WIFI_MODE_FULL_HIGH_PERF, "udp:transfer_wifi")
                wifiLock?.acquire()
            }
        } else {
            window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            wakeLock?.let { if (it.isHeld) it.release() }
            wakeLock = null
            wifiLock?.let { if (it.isHeld) it.release() }
            wifiLock = null
        }
    }
}
