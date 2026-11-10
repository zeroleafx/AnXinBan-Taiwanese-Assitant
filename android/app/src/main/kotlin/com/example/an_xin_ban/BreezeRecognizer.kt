package com.example.an_xin_ban

import android.content.Context
import java.io.File
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest

// Same model as iOS (tool/prepare_breeze_ios.sh).
private const val MODEL_URL =
  "https://huggingface.co/doggy8088/Breeze-ASR-26-GGML/resolve/main/ggml-model-q5_0.bin"
private const val MODEL_SHA256 = "60f25e3a21feca12ec082e6d36f08f94455d9900d6343f7fcb2906f71cc7c449"
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

  /** Downloads and verifies the model if missing. [progress] gets 0..100. */
  fun ensureModel(progress: (Int) -> Unit) {
    val target = modelFile()
    if (target.exists()) return
    val part = File(target.path + ".part")
    var done = if (part.exists()) part.length() else 0L
    val conn = URL(MODEL_URL).openConnection() as HttpURLConnection
    conn.instanceFollowRedirects = true
    conn.connectTimeout = 30_000
    conn.readTimeout = 60_000
    if (done > 0) conn.setRequestProperty("Range", "bytes=$done-")
    try {
      val code = conn.responseCode
      if (code == 200) done = 0
      else if (code != 206) throw SpeechError("語音模型下載失敗（$code）。")
      val total = done + conn.contentLengthLong
      var lastPercent = -1
      conn.inputStream.use { input ->
        FileOutputStream(part, done > 0).use { out ->
          val buffer = ByteArray(1 shl 20)
          while (true) {
            val n = input.read(buffer)
            if (n < 0) break
            out.write(buffer, 0, n)
            done += n
            val percent = if (total > 0) (done * 100 / total).toInt() else 0
            if (percent != lastPercent) {
              lastPercent = percent
              progress(percent)
            }
          }
        }
      }
    } finally {
      conn.disconnect()
    }
    if (sha256(part) != MODEL_SHA256) {
      part.delete()
      throw SpeechError("語音模型檔案損毀，請重新下載。")
    }
    if (!part.renameTo(target)) throw SpeechError("無法儲存語音模型。")
  }

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

  private fun sha256(file: File): String {
    val digest = MessageDigest.getInstance("SHA-256")
    file.inputStream().use { input ->
      val buffer = ByteArray(1 shl 20)
      while (true) {
        val n = input.read(buffer)
        if (n < 0) break
        digest.update(buffer, 0, n)
      }
    }
    return digest.digest().joinToString("") { "%02x".format(it) }
  }
}
