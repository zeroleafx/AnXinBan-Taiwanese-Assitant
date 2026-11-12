package com.example.an_xin_ban

import java.io.File
import java.net.InetAddress
import java.net.ConnectException
import java.net.HttpURLConnection
import java.net.URL
import java.net.ServerSocket
import java.net.Socket
import java.security.MessageDigest
import java.util.Collections
import kotlin.concurrent.thread
import org.junit.After
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class ModelDownloaderTest {
  @get:Rule val folder = TemporaryFolder()

  private val content = ByteArray(300_000) { (it * 31 + it / 7).toByte() }
  private val sha = sha256(content)
  private lateinit var server: FakeServer
  private lateinit var target: File
  private val part
    get() = File(target.path + ".part")

  @Before
  fun start() {
    server = FakeServer(content)
    target = File(folder.root, "model.bin")
  }

  @After fun stop() = server.close()

  private fun downloader(free: Long = Long.MAX_VALUE) =
    ModelDownloader(server.url, sha, content.size.toLong(), target) { free }

  private fun failure(downloader: ModelDownloader = downloader()): String {
    try {
      downloader.ensure {}
    } catch (e: SpeechError) {
      return e.message!!
    }
    fail("Expected the download to fail")
    throw AssertionError()
  }

  @Test
  fun `downloads the file and reports progress up to verification`() {
    val percents = ArrayList<Int>()
    val downloader = downloader()
    assertFalse(downloader.isReady)
    assertEquals(0L, downloader.downloadedBytes)

    downloader.ensure { percents.add(it) }

    assertArrayEquals(content, target.readBytes())
    assertFalse(part.exists())
    assertTrue(downloader.isReady)
    assertEquals(content.size.toLong(), downloader.downloadedBytes)
    assertEquals(listOf<String?>(null), server.ranges)
    assertEquals(percents.sorted(), percents)
    assertEquals(100, percents.last())
    assertEquals(1, percents.count { it == 100 })
  }

  @Test
  fun `does nothing once the file is there`() {
    target.writeBytes(content)
    val percents = ArrayList<Int>()
    downloader().ensure { percents.add(it) }
    assertTrue(server.ranges.isEmpty())
    assertTrue(percents.isEmpty())
  }

  @Test
  fun `continues a partial download from where it stopped`() {
    part.writeBytes(content.copyOf(100_000))
    assertEquals(100_000L, downloader().downloadedBytes)

    downloader().ensure {}

    assertEquals(listOf<String?>("bytes=100000-"), server.ranges)
    assertArrayEquals(content, target.readBytes())
  }

  // The app was closed after the last byte arrived but before the file was
  // verified. Asking the server for "the rest" gets HTTP 416 forever.
  @Test
  fun `verifies a finished download without asking the server again`() {
    part.writeBytes(content)
    val percents = ArrayList<Int>()

    downloader().ensure { percents.add(it) }

    assertTrue(server.ranges.isEmpty())
    assertEquals(listOf(100), percents)
    assertArrayEquals(content, target.readBytes())
    assertFalse(part.exists())
  }

  @Test
  fun `a corrupt file is removed and the next try starts over`() {
    part.writeBytes(content.copyOf().also { it[1234] = (it[1234] + 1).toByte() })

    assertTrue(failure().contains("損毀"))
    assertFalse(part.exists())
    assertFalse(target.exists())

    downloader().ensure {}
    assertEquals(listOf<String?>(null), server.ranges)
    assertArrayEquals(content, target.readBytes())
  }

  @Test
  fun `a dropped connection keeps the partial file and the next try finishes it`() {
    server.cutAfter = 120_000

    assertTrue(failure().contains("中斷"))
    assertFalse(target.exists())
    val kept = part.length()
    assertTrue("kept $kept bytes", kept in 1..120_000)

    downloader().ensure {}
    assertEquals(listOf(null, "bytes=$kept-"), server.ranges)
    assertArrayEquals(content, target.readBytes())
  }

  @Test
  fun `starts over when the server sends the whole file instead of the rest`() {
    part.writeBytes(ByteArray(100_000) { 7 })
    server.ignoreRange = true

    downloader().ensure {}

    assertArrayEquals(content, target.readBytes())
  }

  @Test
  fun `a partial file larger than the model is discarded`() {
    part.writeBytes(content + ByteArray(10))

    downloader().ensure {}

    assertEquals(listOf<String?>(null), server.ranges)
    assertArrayEquals(content, target.readBytes())
  }

  @Test
  fun `refuses to start without enough free space`() {
    assertTrue(failure(downloader(free = 1_000)).contains("空間"))
    assertTrue(server.ranges.isEmpty())
    assertFalse(part.exists())
  }

  @Test
  fun `only the missing part needs to fit`() {
    part.writeBytes(content.copyOf(299_000))
    downloader(free = 1_000).ensure {}
    assertArrayEquals(content, target.readBytes())
  }

  @Test
  fun `a server error is reported and keeps what was downloaded`() {
    part.writeBytes(content.copyOf(100_000))
    server.status = 503

    assertTrue(failure().contains("503"))
    assertEquals(100_000L, part.length())
  }

  @Test
  fun `an unreachable server is reported as a network problem`() {
    var disconnected = false
    val connection = object : HttpURLConnection(URL(server.url)) {
      override fun connect() = Unit
      override fun usingProxy() = false
      override fun disconnect() { disconnected = true }
      override fun getResponseCode(): Int = throw ConnectException("Connection refused")
    }
    val downloader = ModelDownloader(
      server.url, sha, content.size.toLong(), target,
      openConnection = { connection },
    )

    assertEquals("連不上網路，請確認網路後再試一次。", failure(downloader))
    assertTrue(disconnected)
    assertFalse(target.exists())
    assertFalse(part.exists())
  }

  private fun sha256(bytes: ByteArray): String =
    MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }
}

/** A tiny HTTP/1.1 server that serves one file and understands "Range: bytes=N-". */
private class FakeServer(private val content: ByteArray) : AutoCloseable {
  private val socket = ServerSocket(0, 50, InetAddress.getLoopbackAddress())
  val url = "http://127.0.0.1:${socket.localPort}/model.bin"

  /** The Range header of each request, null when there was none. */
  val ranges: MutableList<String?> = Collections.synchronizedList(ArrayList())

  /** Sends only this many body bytes of the next response, then hangs up. */
  @Volatile var cutAfter: Int? = null
  @Volatile var ignoreRange = false
  @Volatile var status: Int? = null

  init {
    thread(isDaemon = true) {
      while (!socket.isClosed) {
        val client =
          try {
            socket.accept()
          } catch (e: Exception) {
            break
          }
        client.use { runCatching { answer(it) } }
      }
    }
  }

  private fun answer(client: Socket) {
    val reader = client.getInputStream().bufferedReader(Charsets.ISO_8859_1)
    var range: String? = null
    while (true) {
      val line = reader.readLine() ?: return
      if (line.isEmpty()) break
      if (line.startsWith("Range:", ignoreCase = true)) range = line.substringAfter(":").trim()
    }
    ranges.add(range)
    val out = client.getOutputStream()
    fun head(statusLine: String, length: Int, extra: String = "") =
      out.write(
        "HTTP/1.1 $statusLine\r\nContent-Length: $length\r\n${extra}Connection: close\r\n\r\n"
          .toByteArray(Charsets.ISO_8859_1)
      )

    val from = if (ignoreRange) 0 else range?.removePrefix("bytes=")?.removeSuffix("-")?.toInt() ?: 0
    val failing = status
    when {
      failing != null -> head("$failing Error", 0)
      from >= content.size -> head("416 Range Not Satisfiable", 0, "Content-Range: bytes */${content.size}\r\n")
      else -> {
        val length = content.size - from
        if (from > 0) {
          head("206 Partial Content", length, "Content-Range: bytes $from-${content.size - 1}/${content.size}\r\n")
        } else {
          head("200 OK", length)
        }
        val sent = cutAfter?.let { minOf(it, length) } ?: length
        cutAfter = null
        out.write(content, from, sent)
      }
    }
    out.flush()
  }

  override fun close() = socket.close()
}
