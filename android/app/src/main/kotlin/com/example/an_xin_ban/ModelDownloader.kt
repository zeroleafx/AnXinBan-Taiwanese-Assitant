package com.example.an_xin_ban

import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest
import java.util.Locale

/**
 * Downloads one large file to [target], continuing where it stopped.
 *
 * Bytes go to "<target>.part", which is renamed to [target] only after its
 * SHA-256 matches, so [target] is either absent or complete. An interrupted
 * download keeps the partial file for the next call.
 *
 * Not thread-safe: call [ensure] from one background thread.
 */
class ModelDownloader(
  private val url: String,
  private val sha256: String,
  val size: Long,
  private val target: File,
  private val freeSpace: () -> Long = {
    target.absoluteFile.parentFile?.usableSpace ?: Long.MAX_VALUE
  },
) {
  private val part = File(target.path + ".part")

  val isReady: Boolean
    get() = target.isFile

  /** Bytes already on the device, so the UI can offer to continue. */
  val downloadedBytes: Long
    get() = if (isReady) size else minOf(part.length(), size)

  /**
   * Makes sure [target] exists. [onPercent] gets 0..99 while downloading, then
   * 100 while the finished file is verified.
   */
  fun ensure(onPercent: (Int) -> Unit) {
    if (isReady) return
    // More bytes than the model has cannot be this model: start over.
    if (part.length() > size) part.delete()
    val have = part.length()
    if (have < size) {
      val missing = size - have
      if (freeSpace() < missing) {
        throw SpeechError("手機空間不夠，還需要 ${gigabytes(missing)} GB。")
      }
      download(have, onPercent)
    }
    // A finished download that was never verified (the app was closed first)
    // gets here without a request. Asking for bytes past the end would be
    // answered with HTTP 416 on every later attempt.
    onPercent(100)
    if (hash(part) != sha256) {
      part.delete()
      throw SpeechError("語音模型檔案損毀，請重新下載。")
    }
    if (!part.renameTo(target)) throw SpeechError("無法儲存語音模型。")
  }

  private fun download(from: Long, onPercent: (Int) -> Unit) {
    val conn = URL(url).openConnection() as HttpURLConnection
    conn.instanceFollowRedirects = true
    conn.connectTimeout = 30_000
    conn.readTimeout = 60_000
    if (from > 0) conn.setRequestProperty("Range", "bytes=$from-")
    var done = from
    try {
      val code =
        try {
          conn.responseCode
        } catch (e: IOException) {
          throw SpeechError("連不上網路，請確認網路後再試一次。")
        }
      when {
        // The server sent the whole file instead of the requested range.
        code == HttpURLConnection.HTTP_OK -> done = 0
        code == HttpURLConnection.HTTP_PARTIAL && continuesAt(conn, from) -> {}
        else -> throw SpeechError("語音模型下載失敗（$code）。")
      }
      var lastPercent = -1
      try {
        conn.inputStream.use { input ->
          FileOutputStream(part, done > 0).use { out ->
            val buffer = ByteArray(1 shl 20)
            while (true) {
              val n = input.read(buffer)
              if (n < 0) break
              out.write(buffer, 0, n)
              done += n
              val percent = minOf(99, (done * 100 / size).toInt())
              if (percent != lastPercent) {
                lastPercent = percent
                onPercent(percent)
              }
            }
          }
        }
      } catch (e: IOException) {
        throw SpeechError(INTERRUPTED)
      }
    } finally {
      conn.disconnect()
    }
    // The connection closed early; the partial file stays for the next try.
    if (done < size) throw SpeechError(INTERRUPTED)
  }

  private fun continuesAt(conn: HttpURLConnection, from: Long): Boolean =
    conn.getHeaderField("Content-Range")?.startsWith("bytes $from-") ?: true

  private fun hash(file: File): String {
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

  private fun gigabytes(bytes: Long): String =
    String.format(Locale.US, "%.1f", maxOf(0.1, bytes / 1e9))

  private companion object {
    const val INTERRUPTED = "下載中斷，再試一次會接著下載。"
  }
}
