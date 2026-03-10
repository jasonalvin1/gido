package com.gido.gido

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterFragmentActivity() {
    private val CHANNEL = "com.gido.gido/file_handler"
    private val BATTERY_CHANNEL = "com.gido.gido/battery"
    private var pendingFilePath: String? = null
    private var pendingContentUri: Uri? = null  // content:// URI 보관 → Dart 요청 시 복사

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIntent(intent)
    }

    private fun handleIntent(intent: Intent?) {
        val action = intent?.action ?: return
        val uri: Uri = intent.data ?: return

        if (action == Intent.ACTION_VIEW) {
            when (uri.scheme) {
                "file" -> {
                    val path = uri.path
                    if (path?.lowercase()?.endsWith(".gido") == true) {
                        pendingFilePath = path
                    }
                }
                "content" -> {
                    // URI만 보관 → Dart가 getInitialFilePath 호출 시 복사 (UI 스레드 블로킹 방지)
                    pendingContentUri = uri
                    pendingFilePath = null
                }
            }
        }
    }

    private fun copyToTemp(uri: Uri): String? {
        return try {
            // content:// URI에서 실제 파일명 가져오기
            val displayName = contentResolver.query(
                uri, null, null, null, null
            )?.use { cursor ->
                val nameIndex = cursor.getColumnIndex(
                    android.provider.OpenableColumns.DISPLAY_NAME
                )
                if (cursor.moveToFirst() && nameIndex >= 0)
                    cursor.getString(nameIndex)
                else null
            } ?: "incoming.gido"

            val tempFile = File(cacheDir, displayName)
            contentResolver.openInputStream(uri)?.use { input ->
                FileOutputStream(tempFile).use { output ->
                    input.copyTo(output)
                }
            }
            tempFile.absolutePath
        } catch (e: Exception) {
            null
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // .gido 파일 핸들러 채널
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getInitialFilePath" -> {
                        // content:// URI가 있으면 지금 복사 (Dart 요청 시점에 처리)
                        if (pendingContentUri != null) {
                            val path = copyToTemp(pendingContentUri!!)
                            pendingContentUri = null
                            if (path?.lowercase()?.endsWith(".gido") == true) {
                                pendingFilePath = path
                            }
                        }
                        result.success(pendingFilePath)
                    }
                    "clearFilePath" -> {
                        pendingFilePath = null
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        // 배터리 최적화 채널 (Samsung 등 알람 미발송 방지)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BATTERY_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isIgnoringBatteryOptimizations" -> {
                        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                        result.success(pm.isIgnoringBatteryOptimizations(packageName))
                    }
                    "requestIgnoreBatteryOptimizations" -> {
                        try {
                            val intent = Intent(
                                Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS
                            ).apply {
                                data = Uri.parse("package:$packageName")
                            }
                            startActivity(intent)
                            result.success(null)
                        } catch (e: Exception) {
                            // 일부 기기에서 직접 요청 불가 시 설정 화면으로 이동
                            val intent = Intent(
                                Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS
                            )
                            startActivity(intent)
                            result.success(null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
