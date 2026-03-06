package com.gido.gido

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterFragmentActivity() {
    private val CHANNEL = "com.gido.gido/file_handler"
    private var pendingFilePath: String? = null

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
            val path: String? = when {
                uri.scheme == "file" -> uri.path
                uri.scheme == "content" -> copyToTemp(uri)
                else -> null
            }
            if (path?.lowercase()?.endsWith(".gido") == true) {
                pendingFilePath = path
            }
        }
    }

    private fun copyToTemp(uri: Uri): String? {
        return try {
            val tempFile = File(cacheDir, "incoming.gido")
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

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getInitialFilePath" -> result.success(pendingFilePath)
                    "clearFilePath" -> {
                        pendingFilePath = null
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
