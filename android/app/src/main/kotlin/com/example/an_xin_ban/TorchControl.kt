package com.example.an_xin_ban

import android.content.Context
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * The flashlight, on the channel `anxinban/torch`. It also follows the light
 * when it is switched elsewhere (quick settings, another app), so the app can
 * show what the light really does.
 */
class TorchControl(context: Context) {
  private val cameras = context.getSystemService(Context.CAMERA_SERVICE) as CameraManager

  // The first camera that has a flash; that is usually the back one.
  private val cameraId: String? = try {
    cameras.cameraIdList.firstOrNull { id ->
      cameras.getCameraCharacteristics(id).get(CameraCharacteristics.FLASH_INFO_AVAILABLE) == true
    }
  } catch (e: Exception) {
    null
  }

  @Volatile
  private var on: Boolean? = null

  private val callback = object : CameraManager.TorchCallback() {
    override fun onTorchModeChanged(id: String, enabled: Boolean) {
      if (id == cameraId) on = enabled
    }

    // The camera is in use, for example by the camera app.
    override fun onTorchModeUnavailable(id: String) {
      if (id == cameraId) on = null
    }
  }

  init {
    // Called right away with the current state, then on every change.
    if (cameraId != null) cameras.registerTorchCallback(callback, Handler(Looper.getMainLooper()))
  }

  fun set(enabled: Boolean): Boolean {
    val id = cameraId ?: return false
    return try {
      cameras.setTorchMode(id, enabled)
      on = enabled
      true
    } catch (e: Exception) {
      false
    }
  }

  fun isOn(): Boolean? = on

  companion object {
    private var shared: TorchControl? = null

    fun register(context: Context, engine: FlutterEngine) {
      val torch = shared ?: TorchControl(context.applicationContext).also { shared = it }
      MethodChannel(engine.dartExecutor.binaryMessenger, "anxinban/torch").setMethodCallHandler { call, result ->
        when (call.method) {
          "set" -> result.success(torch.set(call.arguments as? Boolean ?: false))
          "isOn" -> result.success(torch.isOn())
          else -> result.notImplemented()
        }
      }
    }
  }
}
