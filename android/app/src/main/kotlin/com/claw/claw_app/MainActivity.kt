package com.claw.claw_app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "com.claw.claw_app/background_service"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        ).setMethodCallHandler { call, result ->
            if (call.method == "createNotificationChannel") {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    val channel = NotificationChannel(
                        "1claw_background",
                        "1Claw 后台服务",
                        NotificationManager.IMPORTANCE_LOW
                    )
                    channel.description = "保持 1Claw 在后台运行"
                    val manager = getSystemService(NotificationManager::class.java)
                    manager.createNotificationChannel(channel)
                }
                result.success(true)
            } else {
                result.notImplemented()
            }
        }
    }
}
