package com.bemooks.dot

import android.view.KeyEvent
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var volumeChannel: MethodChannel? = null
    private var screenChannel: MethodChannel? = null
    private var captureVolume = false
    private var foreground = false
    private val capturedKeys = mutableSetOf<Int>()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        screenChannel = MethodChannel(messenger, "dot/screen").also { channel ->
            channel.setMethodCallHandler { call, result ->
                if (call.method == "setKeepAwake" && call.arguments is Boolean) {
                    if (call.arguments == true && foreground) {
                        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    } else {
                        window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    }
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }
        }
        volumeChannel = MethodChannel(messenger, "dot/volume_keys").also { channel ->
            channel.setMethodCallHandler { call, result ->
                if (call.method == "setEnabled" && call.arguments is Boolean) {
                    captureVolume = call.arguments == true && foreground
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }
        }
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        val volumeKey = event.keyCode == KeyEvent.KEYCODE_VOLUME_UP ||
            event.keyCode == KeyEvent.KEYCODE_VOLUME_DOWN
        // Consume the matching key-up even if Dart switched tabs mid-press.
        if (volumeKey && event.action == KeyEvent.ACTION_UP &&
            capturedKeys.remove(event.keyCode)) return true
        if (volumeKey && captureVolume && foreground) {
            if (event.action == KeyEvent.ACTION_DOWN) {
                capturedKeys.add(event.keyCode)
                if (event.repeatCount == 0) {
                    volumeChannel?.invokeMethod(
                        "onVolumeKey",
                        if (event.keyCode == KeyEvent.KEYCODE_VOLUME_UP) "next" else "prev"
                    )
                }
            }
            return true
        }
        // A held key must not start changing volume after a tab switch.
        if (volumeKey && capturedKeys.contains(event.keyCode)) return true
        return super.dispatchKeyEvent(event)
    }

    override fun onResume() {
        foreground = true
        super.onResume()
    }

    override fun onPause() {
        foreground = false
        captureVolume = false
        window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        super.onPause()
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        captureVolume = false
        capturedKeys.clear()
        window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        screenChannel?.setMethodCallHandler(null)
        volumeChannel?.setMethodCallHandler(null)
        screenChannel = null
        volumeChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
