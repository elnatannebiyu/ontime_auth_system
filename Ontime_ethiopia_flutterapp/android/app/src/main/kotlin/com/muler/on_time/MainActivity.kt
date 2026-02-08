package com.muler.on_time

import android.provider.Settings
import android.util.Log
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {
    private val channelName = "ontime/device"
    private val logChannelName = "ontime/log"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getAndroidId" -> {
                        try {
                            val id = Settings.Secure.getString(
                                contentResolver,
                                Settings.Secure.ANDROID_ID
                            )
                            result.success(id)
                        } catch (e: Exception) {
                            result.error("ANDROID_ID_ERROR", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, logChannelName)
            .setMethodCallHandler { call, result ->
                if (call.method == "log") {
                    val message = call.argument<String>("message") ?: ""
                    val level = call.argument<String>("level") ?: "i"
                    when (level.lowercase()) {
                        "e" -> Log.e("OntimeAuth", message)
                        "w" -> Log.w("OntimeAuth", message)
                        "d" -> Log.d("OntimeAuth", message)
                        else -> Log.i("OntimeAuth", message)
                    }
                    result.success(true)
                } else {
                    result.notImplemented()
                }
            }
    }
}
