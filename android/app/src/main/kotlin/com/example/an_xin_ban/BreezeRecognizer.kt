package com.example.an_xin_ban

import android.content.Context
import java.io.File

// Same model as iOS (tool/prepare_breeze_ios.sh).
private const val MODEL_URL =
  "https://huggingface.co/doggy8088/Breeze-ASR-26-GGML/resolve/main/ggml-model-q5_0.bin"
private const val MODEL_SHA256 = "60f25e3a21feca12ec082e6d36f08f94455d9900d6343f7fcb2906f71cc7c449"
private const val MODEL_SIZE = 1_080_732_108L
private const val MODEL_FILE = "ggml-model-q5_0.bin"

internal object WhisperNative {
  init {
    System.loadLibrary("breeze_whisper")
  }

  external fun load(path: String): Long

  external fun free(handle: Long)

  external fun transcribe(handle: Long, samples: FloatArray, threads: Int): ByteArray?
}

/**
 * Breeze-ASR-26 GGML Q5 on whisper.cpp, ported from ios/Breeze/BreezeRecognizer.swift.
 *
 * The 1.08 GB model is downloaded once into the app's external files dir.
 * During development it can be pushed there instead:
 *   adb push ggml-model-q5_0.bin /sdcard/Android/data/com.example.an_xin_ban/files/
 *
 * Not thread-safe: call every method from one background thread.
 */
class BreezeRecognizer(private val context: Context) {
  private var handle = 0L

  fun modelFile(): File = File(context.getExternalFilesDir(null) ?: context.filesDir, MODEL_FILE)

  private val downloader by lazy {
    ModelDownloader(MODEL_URL, MODEL_SHA256, MODEL_SIZE, modelFile())
  }

  /** Whether the model is on the device and how much of it is downloaded. Any thread. */
  fun modelStatus(): Map<String, Any> =
    mapOf(
      "ready" to downloader.isReady,
      "totalBytes" to MODEL_SIZE,
      "downloadedBytes" to downloader.downloadedBytes,
    )

  /** Downloads and verifies the model if missing. [progress] gets 0..100. */
  fun ensureModel(progress: (Int) -> Unit) = downloader.ensure(progress)

  fun transcribe(path: String): String {
    if (handle == 0L) {
      handle = WhisperNative.load(modelFile().path)
      if (handle == 0L) throw SpeechError("無法載入台語辨識模型。")
    }
    val parts = ArrayList<String>()
    readSpeechWindows(path) { samples ->
      val bytes = WhisperNative.transcribe(handle, samples, 4) ?: throw SpeechError("台語辨識失敗。")
      parts.add(String(bytes, Charsets.UTF_8))
    }
    return parts.joinToString("").trim()
  }

  /** Frees the model's memory; the next transcription reloads it. */
  fun releaseModel() {
    if (handle != 0L) WhisperNative.free(handle)
    handle = 0L
  }
}
