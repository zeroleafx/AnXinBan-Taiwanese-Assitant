package com.example.an_xin_ban

import java.io.File
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.channels.FileChannel

/** Input and output tensor names of one signature, in model order. */
class SignatureNames(val inputs: List<String>, val outputs: List<String>)

/**
 * Reads signature_defs from a .tflite flatbuffer header.
 *
 * The LiteRT Kotlin API runs signatures by tensor name but cannot list those
 * names, so they are read from the file (tflite schema: Model.signature_defs is
 * field 7; SignatureDef is inputs(0), outputs(1), signature_key(2); TensorMap is
 * name(0)).
 */
fun readTfliteSignatures(file: File): Map<String, SignatureNames> {
  RandomAccessFile(file, "r").use { raf ->
    val size = minOf(raf.length(), Int.MAX_VALUE.toLong())
    val buf = raf.channel.map(FileChannel.MapMode.READ_ONLY, 0, size)
    buf.order(ByteOrder.LITTLE_ENDIAN)
    return FlatTables(buf).signatures()
  }
}

private class FlatTables(private val b: ByteBuffer) {
  private fun field(table: Int, id: Int): Int? {
    val vtable = table - b.getInt(table)
    val vtableSize = b.getShort(vtable).toInt() and 0xffff
    val slot = 4 + 2 * id
    if (slot >= vtableSize) return null
    val offset = b.getShort(vtable + slot).toInt() and 0xffff
    return if (offset == 0) null else table + offset
  }

  private fun deref(pos: Int) = pos + b.getInt(pos)

  private fun tables(table: Int, id: Int): List<Int> {
    val pos = field(table, id) ?: return emptyList()
    val vector = deref(pos)
    return (0 until b.getInt(vector)).map { deref(vector + 4 + 4 * it) }
  }

  private fun string(table: Int, id: Int): String {
    val pos = field(table, id) ?: return ""
    val s = deref(pos)
    val bytes = ByteArray(b.getInt(s))
    for (i in bytes.indices) bytes[i] = b.get(s + 4 + i)
    return String(bytes, Charsets.UTF_8)
  }

  fun signatures(): Map<String, SignatureNames> {
    val model = deref(0)
    return tables(model, 7).associate { sig ->
      string(sig, 2) to
        SignatureNames(
          tables(sig, 0).map { string(it, 0) },
          tables(sig, 1).map { string(it, 0) },
        )
    }
  }
}
