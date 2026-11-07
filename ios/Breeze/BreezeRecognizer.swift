import Foundation

func transcribeRecording(at url: URL) throws -> String {
  func asset(_ name: String, _ ext: String) throws -> URL {
    guard let url = Bundle.main.url(forResource: name, withExtension: ext) else {
      throw SpeechError("Missing " + name)
    }
    return url
  }

  let env = try Environment()
  let options = try Options()
  try options.setHardwareAccelerators([.cpu])
  let cpu = try CpuOptions()
  try cpu.setNumThreads(4)
  try options.addConcreteOptions(cpu)
  let model = try CompiledModel(
    filePath: asset("model", "tflite").path, environment: env, options: options)
  let keys = try model.signatureKeys()
  guard let enc = keys.firstIndex(of: "encode"), let dec = keys.firstIndex(of: "decode") else {
    throw SpeechError("Missing model signatures")
  }
  let melData = try Data(contentsOf: asset("mel", "bin"))
  guard melData.count == 80 * 201 * 4 else { throw SpeechError("無法讀取語音模型設定。") }
  let extractor = SpeechFeatures(
    mel: melData.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) })
  let features = try model.createInputBuffers(signatureIndex: enc)
  let cross = try model.createOutputBuffers(signatureIndex: enc)
  var shared = [String: TensorBuffer]()
  for (i, b) in cross.enumerated() {
    shared[try model.outputName(outputIndex: i, signatureIndex: enc)] = b
  }
  var inputs = [TensorBuffer]()
  for i in 0..<(try model.inputCount(signatureIndex: dec)) {
    let name = try model.inputName(inputIndex: i, signatureIndex: dec)
    if let buffer = shared[name] {
      inputs.append(buffer)
      continue
    }
    let req = try model.inputBufferRequirements(inputIndex: i, signatureIndex: dec)
    let buffer = try TensorBuffer(
      environment: env, bufferType: req.supportedTypes.first ?? .hostMemory,
      tensorType: model.inputTensorType(inputIndex: i, signatureIndex: dec), size: req.bufferSize)
    if name.hasPrefix("kv_cache_") { try buffer.write(Data(count: req.bufferSize)) }
    inputs.append(buffer)
    shared[name] = buffer
  }
  var outputs = [TensorBuffer]()
  for i in 0..<(try model.outputCount(signatureIndex: dec)) {
    let name = try model.outputName(outputIndex: i, signatureIndex: dec)
    if let buffer = shared[name] {
      outputs.append(buffer)
      continue
    }
    let req = try model.outputBufferRequirements(outputIndex: i, signatureIndex: dec)
    let buffer = try TensorBuffer(
      environment: env, bufferType: req.supportedTypes.first ?? .hostMemory,
      tensorType: model.outputTensorType(outputIndex: i, signatureIndex: dec), size: req.bufferSize)
    outputs.append(buffer)
    shared[name] = buffer
  }
  guard let token = shared["tokens"], let position = shared["input_pos"],
    let logits = shared["logits"]
  else { throw SpeechError("Missing decoder tensors") }
  let config =
    try JSONSerialization.jsonObject(with: Data(contentsOf: asset("config", "json")))
    as? [String: Any]
  let vocab = try JSONDecoder().decode(
    [Int: Data].self, from: Data(contentsOf: asset("tokens", "json")))
  let suppress = Set(config?["suppress_tokens"] as? [Int] ?? [])
  let begin = Set(config?["begin_suppress_tokens"] as? [Int] ?? [])
  let prompt = [50258, 50260, 50359, 50363]
  var texts = [String]()
  try readSpeechWindows(url) { samples in
    try features[0].write(extractor.compute(samples))
    try model.run(inputs: features, outputs: cross, signatureIndex: enc)
    var next = prompt[0]
    var bytes = Data()
    for p in 0..<256 {
      try token.write([Int32(next)])
      try position.write([Int32(p)])
      try model.run(inputs: inputs, outputs: outputs, signatureIndex: dec)
      if p + 1 < prompt.count {
        next = prompt[p + 1]
        continue
      }
      let values: [Float] = try logits.read()
      var best = -Float.infinity
      for i in 0..<min(values.count, 51865)
      where !suppress.contains(i) && !(p == 3 && begin.contains(i)) && values[i] > best {
        best = values[i]
        next = i
      }
      if next == 50257 { break }
      if let b = vocab[next] { bytes.append(b) }
    }
    texts.append(String(decoding: bytes, as: UTF8.self))
  }
  return texts.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
}
