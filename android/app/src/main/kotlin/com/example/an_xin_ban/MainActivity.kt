package com.example.an_xin_ban

import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "anxinban/breeze")
    val main = Handler(Looper.getMainLooper())
    val speech = recognizer ?: BreezeRecognizer(applicationContext).also { recognizer = it }
    channel.setMethodCallHandler { call, result ->
      val path = call.arguments as? String
      if (call.method != "transcribe" || path == null) {
        result.notImplemented()
        return@setMethodCallHandler
      }
      speechExecutor.execute {
        try {
          speech.ensureModel { percent ->
            main.post { channel.invokeMethod("downloadProgress", percent) }
          }
          main.post { channel.invokeMethod("downloadProgress", null) }
          val text = speech.transcribe(path)
          main.post { result.success(text) }
        } catch (e: Throwable) {
          main.post {
            channel.invokeMethod("downloadProgress", null)
            result.error("speech", e.message, null)
          }
        }
      }
    }
  }

  companion object {
    // LiteRT model creation and inference must stay on one thread.
    private val speechExecutor = Executors.newSingleThreadExecutor()
    // Kept across activity recreation so the loaded model is reused.
    private var recognizer: BreezeRecognizer? = null
  }
}
