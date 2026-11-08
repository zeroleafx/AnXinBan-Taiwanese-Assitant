import Foundation
import whisper

// All access to this recognizer is serialized by the Flutter channel's speech queue.
final class BreezeRecognizer {
  private var context: OpaquePointer?

  func releaseModel() {
    if let context { whisper_free(context) }
    context = nil
  }

  deinit { releaseModel() }

  private func loadModel() throws -> OpaquePointer {
    if let context { return context }
    guard let path = Bundle.main.path(forResource: "ggml-model-q5_0", ofType: "bin") else {
      throw SpeechError("找不到台語辨識模型。")
    }
    var options = whisper_context_default_params()
    options.use_gpu = false
    guard let loaded = whisper_init_from_file_with_params(path, options) else {
      throw SpeechError("無法載入台語辨識模型。")
    }
    context = loaded
    return loaded
  }

  func transcribe(at url: URL) throws -> String {
    let model = try loadModel()
    var parts = [String]()
    try "zh".withCString { language in
      var options = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
      options.language = language
      options.n_threads = 4
      options.no_context = true
      options.no_timestamps = true
      options.translate = false
      options.print_progress = false
      options.print_realtime = false
      try readSpeechWindows(url) { samples in
        let status = samples.withUnsafeBufferPointer {
          whisper_full(model, options, $0.baseAddress, Int32($0.count))
        }
        guard status == 0 else { throw SpeechError("台語辨識失敗。") }
        for i in 0..<whisper_full_n_segments(model) {
          if let text = whisper_full_get_segment_text(model, i) {
            parts.append(String(cString: text))
          }
        }
      }
    }
    return parts.joined().trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
