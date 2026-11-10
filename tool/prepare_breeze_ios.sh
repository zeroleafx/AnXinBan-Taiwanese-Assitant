#!/bin/bash
set -eu
cd "$(dirname "$0")/../ios/Breeze"
mkdir -p .build
cd .build
if [ -d whisper.xcframework ]; then
  exit 0
fi
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
fetch() {
  curl --fail --location --retry 3 --output "$stage/$2" "$1"
  (cd "$stage" && echo "$3  $2" | shasum -a 256 -c -)
}
if ! [ -d whisper.xcframework ]; then
  fetch 'https://github.com/ggml-org/whisper.cpp/releases/download/b5454/whisper-b5454-xcframework.zip' runtime.zip e57f8c48933000acabc13bb913fbe82805d483a2deff692cc6738836bd92393b
  unzip -q "$stage/runtime.zip" -d "$stage"
  mv "$stage/build-apple/whisper.xcframework" .
fi
