package com.example.an_xin_ban

import android.content.ComponentCallbacks2
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.Handler
import android.os.Looper
import android.view.WindowManager
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
    val reportProgress = { percent: Int ->
      main.post { channel.invokeMethod("downloadProgress", percent) }
      Unit
    }
    channel.setMethodCallHandler { call, result ->
      when (call.method) {
        // With these two the UI can ask before the large download and show
        // whether it would use mobile data, instead of it starting unasked.
        "modelStatus" -> result.success(speech.modelStatus() + ("network" to networkKind()))
        "downloadModel" -> {
          window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
          speechExecutor.execute {
            val error = runCatching { speech.ensureModel(reportProgress) }.exceptionOrNull()
            main.post {
              window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
              channel.invokeMethod("downloadProgress", null)
              if (error == null) result.success(null)
              else result.error("download", error.message, null)
            }
          }
        }
        "transcribe" -> {
          val path = call.arguments as? String
          if (path == null) {
            result.notImplemented()
            return@setMethodCallHandler
          }
          speechExecutor.execute {
            try {
              if (speech.modelStatus()["ready"] != true) throw SpeechError("請先下載語音模型。")
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
        else -> result.notImplemented()
      }
    }
  }

  /** "none", "metered" (mobile data) or "unmetered" (usually Wi-Fi). */
  private fun networkKind(): String {
    val manager = getSystemService(ConnectivityManager::class.java) ?: return "none"
    val capabilities = manager.getNetworkCapabilities(manager.activeNetwork) ?: return "none"
    return when {
      !capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) -> "none"
      capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED) -> "unmetered"
      else -> "metered"
    }
  }

  // Like iOS's memory warning: drop the ~1.6 GB model when the system needs memory.
  override fun onTrimMemory(level: Int) {
    super.onTrimMemory(level)
    if (level >= ComponentCallbacks2.TRIM_MEMORY_BACKGROUND) {
      speechExecutor.execute { recognizer?.releaseModel() }
    }
  }

  companion object {
    // LiteRT model creation and inference must stay on one thread.
    private val speechExecutor = Executors.newSingleThreadExecutor()
    // Kept across activity recreation so the loaded model is reused.
    private var recognizer: BreezeRecognizer? = null
  }
}
