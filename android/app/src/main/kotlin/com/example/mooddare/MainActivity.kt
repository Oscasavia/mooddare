package com.example.mooddare

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var beauty: BeautyPlugin? = null
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        beauty = BeautyPlugin(applicationContext)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "mooddare/beauty")
            .setMethodCallHandler(beauty)
    }
    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "mooddare/beauty")
            .setMethodCallHandler(null)
        beauty?.close()
        beauty = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
