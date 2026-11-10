package com.example.an_xin_ban

import android.media.AudioFormat
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import java.nio.ByteOrder
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

class SpeechError(message: String) : Exception(message)

private const val WINDOW = 480000 // 30 s at 16 kHz

/** Decodes an AAC/.m4a recording and passes 16 kHz mono windows of at most 30 s. */
fun readSpeechWindows(path: String, consume: (FloatArray) -> Unit) {
  val samples = decodeMono16k(path)
  if (samples.isEmpty()) throw SpeechError("錄音沒有聲音資料。")
  var start = 0
  while (start < samples.size) {
    val end = min(start + WINDOW, samples.size)
    consume(samples.copyOfRange(start, end))
    start = end
  }
}

private fun decodeMono16k(path: String): FloatArray {
  val extractor = MediaExtractor()
  extractor.setDataSource(path)
  val track =
    (0 until extractor.trackCount).firstOrNull {
      extractor.getTrackFormat(it).getString(MediaFormat.KEY_MIME)?.startsWith("audio/") == true
    } ?: run {
      extractor.release()
      throw SpeechError("錄音沒有音軌。")
    }
  extractor.selectTrack(track)
  val format = extractor.getTrackFormat(track)
  val codec = MediaCodec.createDecoderByType(format.getString(MediaFormat.KEY_MIME)!!)
  var rate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
  var channels = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
  var floatPcm = false
  val mono = FloatList()
  try {
    codec.configure(format, null, null, 0)
    codec.start()
    val info = MediaCodec.BufferInfo()
    var inputDone = false
    while (true) {
      if (!inputDone) {
        val index = codec.dequeueInputBuffer(10_000)
        if (index >= 0) {
          val input = codec.getInputBuffer(index)!!
          val size = extractor.readSampleData(input, 0)
          if (size < 0) {
            codec.queueInputBuffer(index, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
            inputDone = true
          } else {
            codec.queueInputBuffer(index, 0, size, extractor.sampleTime, 0)
            extractor.advance()
          }
        }
      }
      val out = codec.dequeueOutputBuffer(info, 10_000)
      if (out == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
        val f = codec.outputFormat
        rate = f.getInteger(MediaFormat.KEY_SAMPLE_RATE)
        channels = f.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
        floatPcm =
          f.containsKey(MediaFormat.KEY_PCM_ENCODING) &&
            f.getInteger(MediaFormat.KEY_PCM_ENCODING) == AudioFormat.ENCODING_PCM_FLOAT
      } else if (out >= 0) {
        val data = codec.getOutputBuffer(out)!!.order(ByteOrder.LITTLE_ENDIAN)
        data.position(info.offset)
        data.limit(info.offset + info.size)
        if (floatPcm) {
          val pcm = data.asFloatBuffer()
          while (pcm.remaining() >= channels) {
            var sum = 0f
            repeat(channels) { sum += pcm.get() }
            mono.add(sum / channels)
          }
        } else {
          val pcm = data.asShortBuffer()
          while (pcm.remaining() >= channels) {
            var sum = 0f
            repeat(channels) { sum += pcm.get() / 32768f }
            mono.add(sum / channels)
          }
        }
        codec.releaseOutputBuffer(out, false)
        if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) break
      }
    }
  } catch (e: SpeechError) {
    throw e
  } catch (e: Exception) {
    throw SpeechError("音訊解碼失敗。")
  } finally {
    runCatching { codec.stop() }
    codec.release()
    extractor.release()
  }
  return resample(mono.toArray(), rate, 16000)
}

/** Windowed-sinc resampler with a low-pass cutoff below the lower Nyquist rate. */
private fun resample(input: FloatArray, from: Int, to: Int): FloatArray {
  if (from == to || input.isEmpty()) return input
  val ratio = to.toDouble() / from
  val cutoff = min(1.0, ratio) * 0.95
  val half = 16
  val radius = half / cutoff
  val out = FloatArray(floor(input.size * ratio).toInt())
  for (n in out.indices) {
    val center = n / ratio
    val lo = max(0, (center - radius).toInt())
    val hi = min(input.size - 1, (center + radius).toInt())
    var acc = 0.0
    var norm = 0.0
    for (k in lo..hi) {
      val x = (k - center) * cutoff
      val sinc = if (abs(x) < 1e-9) 1.0 else sin(PI * x) / (PI * x)
      val w = 0.5 + 0.5 * cos(PI * (k - center) / radius)
      val h = sinc * w
      acc += input[k] * h
      norm += h
    }
    out[n] = if (norm != 0.0) (acc / norm).toFloat() else 0f
  }
  return out
}

private class FloatList {
  private var data = FloatArray(1 shl 16)
  private var size = 0
  fun add(v: Float) {
    if (size == data.size) data = data.copyOf(size * 2)
    data[size++] = v
  }
  fun toArray(): FloatArray = data.copyOf(size)
}
