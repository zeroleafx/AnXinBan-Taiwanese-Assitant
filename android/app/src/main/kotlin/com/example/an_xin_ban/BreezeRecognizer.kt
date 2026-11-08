package com.example.an_xin_ban

import android.content.Context
import android.util.Base64
import com.google.ai.edge.litert.Accelerator
import com.google.ai.edge.litert.CompiledModel
import com.google.ai.edge.litert.Environment
import com.google.ai.edge.litert.TensorBuffer
import com.google.ai.edge.litert.TensorType
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.security.MessageDigest
import org.json.JSONArray
import org.json.JSONObject

private const val MODEL_URL =
  "https://huggingface.co/litert-community/Breeze-ASR-26-LiteRT/resolve/main/breeze_asr_26_30s_i8_kv256.tflite"
private const val MODEL_SHA256 = "f32de6eaf89ec67f4f90ea5b75c1206850ad094e067c6dc32d7621be7a96a55d"
private const val MODEL_FILE = "breeze_asr_26_30s_i8_kv256.tflite"

/**
 * Breeze-ASR-26 on LiteRT, ported from ios/Breeze/BreezeRecognizer.swift.
 *
 * The 1.57 GB model is too large to ship in the APK (LiteRT's asset loader copies
 * it into memory), so it is downloaded once into the app's external files dir.
 * During development it can be pushed there instead:
 *   adb push model.tflite /sdcard/Android/data/com.example.an_xin_ban/files/breeze_asr_26_30s_i8_kv256.tflite
 *
 * Not thread-safe: call every method from one background thread.
 */
class BreezeRecognizer(private val context: Context) {
  private var engine: Engine? = null

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
    val e = engine ?: Engine(context, modelFile()).also { engine = it }
    return e.transcribe(path)
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

private class Engine(context: Context, model: File) {
  private val env = Environment.create()
  private val compiled: CompiledModel
  private val features: TensorBuffer
  private val encodeInputs: Map<String, TensorBuffer>
  private val encodeOutputs: Map<String, TensorBuffer>
  private val decodeInputs: Map<String, TensorBuffer>
  private val decodeOutputs: Map<String, TensorBuffer>
  private val token: TensorBuffer
  private val position: TensorBuffer
  private val logits: TensorBuffer
  private val extractor: SpeechFeatures
  private val vocab: Map<Int, ByteArray>
  private val suppress: Set<Int>
  private val beginSuppress: Set<Int>

  init {
    val signatures = readTfliteSignatures(model)
    val enc = signatures["encode"] ?: throw SpeechError("Missing model signatures")
    val dec = signatures["decode"] ?: throw SpeechError("Missing model signatures")
    val options = CompiledModel.Options(Accelerator.CPU)
    options.cpuOptions = CompiledModel.CpuOptions(numThreads = 4)
    compiled = CompiledModel.create(model.path, options, env)

    // Encoder outputs (cross-attention K/V) are decoder inputs of the same name,
    // and the decoder's KV-cache outputs alias its inputs, as on iOS.
    val shared = HashMap<String, TensorBuffer>()
    encodeInputs = enc.inputs.associateWith { compiled.createInputBuffer(it, "encode") }
    features = encodeInputs.values.first()
    encodeOutputs =
      enc.outputs.associateWith { name ->
        compiled.createOutputBuffer(name, "encode").also { shared[name] = it }
      }
    decodeInputs =
      dec.inputs.associateWith { name ->
        shared.getOrPut(name) {
          compiled.createInputBuffer(name, "decode").also {
            if (name.startsWith("kv_cache_")) zero(it, compiled.getInputTensorType(name, "decode"))
          }
        }
      }
    decodeOutputs =
      dec.outputs.associateWith { name ->
        shared.getOrPut(name) { compiled.createOutputBuffer(name, "decode") }
      }
    token = shared["tokens"] ?: throw SpeechError("Missing decoder tensors")
    position = shared["input_pos"] ?: throw SpeechError("Missing decoder tensors")
    logits = shared["logits"] ?: throw SpeechError("Missing decoder tensors")

    val assets = context.assets
    val melBytes = assets.open("mel.bin").use { it.readBytes() }
    if (melBytes.size != 80 * 201 * 4) throw SpeechError("無法讀取語音模型設定。")
    val mel = FloatArray(80 * 201)
    ByteBuffer.wrap(melBytes).order(ByteOrder.LITTLE_ENDIAN).asFloatBuffer().get(mel)
    extractor = SpeechFeatures(mel)

    val config = JSONObject(assets.open("config.json").use { String(it.readBytes()) })
    suppress = ints(config.optJSONArray("suppress_tokens"))
    beginSuppress = ints(config.optJSONArray("begin_suppress_tokens"))
    val tokens = JSONObject(assets.open("tokens.json").use { String(it.readBytes()) })
    vocab = HashMap<Int, ByteArray>(tokens.length() * 2).apply {
      for (key in tokens.keys()) put(key.toInt(), Base64.decode(tokens.getString(key), Base64.DEFAULT))
    }
  }

  fun transcribe(path: String): String {
    val prompt = intArrayOf(50258, 50260, 50359, 50363)
    val texts = ArrayList<String>()
    readSpeechWindows(path) { samples ->
      features.writeFloat(extractor.compute(samples))
      compiled.run(encodeInputs, encodeOutputs, "encode")
      var next = prompt[0]
      val bytes = ByteArrayOutputStream()
      for (p in 0 until 256) {
        token.writeInt(intArrayOf(next))
        position.writeInt(intArrayOf(p))
        compiled.run(decodeInputs, decodeOutputs, "decode")
        if (p + 1 < prompt.size) {
          next = prompt[p + 1]
          continue
        }
        val values = logits.readFloat()
        var best = Float.NEGATIVE_INFINITY
        for (i in 0 until minOf(values.size, 51865)) {
          if (i in suppress || (p == 3 && i in beginSuppress)) continue
          if (values[i] > best) {
            best = values[i]
            next = i
          }
        }
        if (next == 50257) break
        vocab[next]?.let { bytes.write(it) }
      }
      texts.add(bytes.toString(Charsets.UTF_8.name()))
    }
    return texts.joinToString(" ").trim()
  }

  private fun zero(buffer: TensorBuffer, type: TensorType) {
    when (type.elementType) {
      TensorType.ElementType.FLOAT -> buffer.writeFloat(FloatArray(buffer.readFloat().size))
      TensorType.ElementType.INT8 -> buffer.writeInt8(ByteArray(buffer.readInt8().size))
      TensorType.ElementType.INT -> buffer.writeInt(IntArray(buffer.readInt().size))
      TensorType.ElementType.INT64 -> buffer.writeLong(LongArray(buffer.readLong().size))
      TensorType.ElementType.BOOLEAN -> buffer.writeBoolean(BooleanArray(buffer.readBoolean().size))
    }
  }

  private fun ints(array: JSONArray?): Set<Int> =
    if (array == null) emptySet() else (0 until array.length()).map { array.getInt(it) }.toSet()
}
