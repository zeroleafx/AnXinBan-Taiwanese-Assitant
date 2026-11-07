#!/bin/bash
set -eu
cd "$(dirname "$0")/../ios/Breeze"
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
fetch() {
  curl --fail --location --retry 3 --output "$stage/$2" "$1"
  (cd "$stage" && echo "$3  $2" | shasum -a 256 -c -)
}
if ! [ -f Assets/model.tflite ]; then
  fetch 'https://huggingface.co/litert-community/Breeze-ASR-26-LiteRT/resolve/main/breeze_asr_26_30s_i8_kv256.tflite' model.tflite f32de6eaf89ec67f4f90ea5b75c1206850ad094e067c6dc32d7621be7a96a55d
  mv "$stage/model.tflite" Assets/
fi
if ! [ -d CLiteRT.xcframework ]; then
  fetch 'https://github.com/google-ai-edge/LiteRT/releases/download/v2.3.0/CLiteRT.xcframework.zip' runtime.zip b36a1a4f1b3eeb04546b4cc2986902cd704439b37c34597ab0f804aed08f5a00
  unzip -q "$stage/runtime.zip" -d "$stage"
  mv "$stage/CLiteRT.xcframework" .
fi
