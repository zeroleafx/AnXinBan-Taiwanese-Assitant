package com.example.an_xin_ban

import android.content.ComponentCallbacks2
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

  // Like iOS's memory warning: drop the ~1 GB model when the system needs memory.
  override fun onTrimMemory(level: Int) {
    super.onTrimMemory(level)
    if (level >= ComponentCallbacks2.TRIM_MEMORY_BACKGROUND) {
      speechExecutor.execute { recognizer?.releaseModel() }
    }
  }

  companion object {
    // whisper.cpp calls must be serialized, so all speech work runs on one thread.
    private val speechExecutor = Executors.newSingleThreadExecutor()
    // Kept across activity recreation so the loaded model is reused.
    private var recognizer: BreezeRecognizer? = null
  }
}
