import AVFoundation
import Accelerate
import Foundation

struct SpeechError: LocalizedError {
  let message: String
  init(_ message: String) { self.message = message }
  var errorDescription: String? { message }
}

// Read 16 kHz mono PCM in bounded windows, even for long AAC recordings.
func readSpeechWindows(_ url: URL, consume: ([Float]) throws -> Void) throws {
  let asset = AVURLAsset(url: url)
  guard let track = asset.tracks(withMediaType: .audio).first else { throw SpeechError("錄音沒有音軌。") }
  let reader = try AVAssetReader(asset: asset)
  let output = AVAssetReaderTrackOutput(
    track: track,
    outputSettings: [
      AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16000,
      AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 32,
      AVLinearPCMIsFloatKey: true, AVLinearPCMIsNonInterleaved: false,
      AVLinearPCMIsBigEndianKey: false,
    ])
  reader.add(output)
  guard reader.startReading() else { throw reader.error ?? SpeechError("無法讀取錄音。") }
  defer { reader.cancelReading() }
  var window = [Float]()
  window.reserveCapacity(480000)
  var hadSamples = false
  while let sample = output.copyNextSampleBuffer() {
    guard let block = CMSampleBufferGetDataBuffer(sample) else { throw SpeechError("無法讀取音訊資料。") }
    let size = CMBlockBufferGetDataLength(block)
    var samples = [Float](repeating: 0, count: size / 4)
    guard size % 4 == 0, size > 0 else { continue }
    let status = samples.withUnsafeMutableBytes {
      CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: size, destination: $0.baseAddress!)
    }
    guard status == noErr else { throw SpeechError("音訊解碼失敗。") }
    hadSamples = true
    var i = 0
    while i < samples.count {
      let end = min(i + 480000 - window.count, samples.count)
      window.append(contentsOf: samples[i..<end])
      i = end
      if window.count == 480000 {
        try consume(window)
        window.removeAll(keepingCapacity: true)
      }
    }
  }
  guard reader.status == .completed else { throw reader.error ?? SpeechError("錄音解碼中斷。") }
  guard hadSamples else { throw SpeechError("錄音沒有聲音資料。") }
  if !window.isEmpty { try consume(window) }
}

struct SpeechFeatures {
  let mel: [Float]
  // Fourier coefficients include Whisper's periodic 400-sample Hann window.
  private static let basis: [Float] = (0..<402).flatMap { row in
    (0..<400).map { i in
      let phase = 2 * Double.pi * Double(row % 201) * Double(i) / 400
      let hann = 0.5 - 0.5 * cos(2 * Double.pi * Double(i) / 400)
      return Float(hann * (row < 201 ? cos(phase) : sin(phase)))
    }
  }
  func compute(_ samples: [Float]) -> [Float] {
    let frames = min(3000, (samples.count + 359) / 160)
    var framed = [Float](repeating: 0, count: 400 * frames)
    for t in 0..<frames {
      for i in 0..<400 {
        var j = abs(t * 160 + i - 200)
        if j >= 480000 { j = 959998 - j }
        if j < samples.count { framed[i * frames + t] = samples[j] }
      }
    }
    var spectrum = [Float](repeating: 0, count: 402 * frames)
    vDSP_mmul(Self.basis, 1, framed, 1, &spectrum, 1, 402, vDSP_Length(frames), 400)
    let bins = 201 * frames
    for i in 0..<bins {
      spectrum[i] = spectrum[i] * spectrum[i] + spectrum[i + bins] * spectrum[i + bins]
    }
    var energy = [Float](repeating: 0, count: 80 * frames)
    vDSP_mmul(mel, 1, spectrum, 1, &energy, 1, 80, vDSP_Length(frames), 201)
    let floor = max(-10, log10(max(1e-10, energy.max() ?? 0)) - 8)
    var values = [Float](repeating: (floor + 4) / 4, count: 80 * 3000)
    for band in 0..<80 {
      for t in 0..<frames {
        values[band * 3000 + t] = (max(floor, log10(max(1e-10, energy[band * frames + t]))) + 4) / 4
      }
    }
    return values
  }
}
