package com.example.mooddare

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var beauty: BeautyPlugin? = null
    private var liveBeauty: LiveBeautyPlugin? = null
    override fun onPause() {
        liveBeauty?.onPause()
        super.onPause()
    }
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        liveBeauty?.onPermissionResult(requestCode, grantResults)
    }
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "mooddare/settings")
            .setMethodCallHandler(SettingsPlugin(this))
        beauty = BeautyPlugin(applicationContext)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "mooddare/beauty")
            .setMethodCallHandler(beauty)
        liveBeauty = LiveBeautyPlugin(this, flutterEngine.renderer)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "mooddare/live_beauty")
            .setMethodCallHandler(liveBeauty)
    }
    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "mooddare/live_beauty")
            .setMethodCallHandler(null)
        liveBeauty?.close()
        liveBeauty = null
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "mooddare/beauty")
            .setMethodCallHandler(null)
        beauty?.close()
        beauty = null
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "mooddare/settings")
            .setMethodCallHandler(null)
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
