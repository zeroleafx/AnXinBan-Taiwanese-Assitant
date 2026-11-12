package com.example.an_xin_ban

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/**
 * Lists the apps on the home screen and opens one by package, for voice
 * commands such as "打開相機".
 *
 * Needs the MAIN/LAUNCHER <queries> entry in the manifest: without it
 * Android 11 and later hide other apps from this one.
 */
object AppLauncher {
  private val worker = Executors.newSingleThreadExecutor()

  fun register(activity: Activity, flutterEngine: FlutterEngine) {
    val main = Handler(Looper.getMainLooper())
    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "anxinban/apps")
      .setMethodCallHandler { call, result ->
        when (call.method) {
          // Reading every app's name takes a moment, so not on the UI thread.
          "list" ->
            worker.execute {
              val apps = runCatching { launcherApps(activity) }.getOrDefault(emptyList())
              main.post { result.success(apps) }
            }
          "launch" -> result.success(launch(activity, call.arguments as? String))
          else -> result.notImplemented()
        }
      }
  }

  private fun launcherApps(activity: Activity): List<Map<String, String>> {
    val manager = activity.packageManager
    val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
    val found =
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
        manager.queryIntentActivities(intent, PackageManager.ResolveInfoFlags.of(0))
      } else {
        @Suppress("DEPRECATION") manager.queryIntentActivities(intent, 0)
      }
    return found
      .filter { it.activityInfo.packageName != activity.packageName }
      .map {
        mapOf(
          "label" to it.loadLabel(manager).toString(),
          "package" to it.activityInfo.packageName,
        )
      }
  }

  private fun launch(activity: Activity, packageName: String?): Boolean {
    val intent =
      packageName?.let { activity.packageManager.getLaunchIntentForPackage(it) } ?: return false
    return try {
      activity.startActivity(intent)
      true
    } catch (e: ActivityNotFoundException) {
      false
    }
  }
}
