import AVFoundation
import Foundation

struct SpeechError: LocalizedError {
  let message: String
  init(_ message: String) { self.message = message }
  var errorDescription: String? { message }
}

// Read 16 kHz mono PCM in bounded windows, even for long AAC recordings.
func readSpeechWindows(_ asset: AVAsset, track: AVAssetTrack, consume: ([Float]) throws -> Void) throws {
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
