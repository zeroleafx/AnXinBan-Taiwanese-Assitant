# 安心BAN · AnXinBan

A Flutter home-page prototype for a Taiwanese-language voice assistant.

## Run

```sh
flutter pub get
flutter run -d chrome
```

Use `flutter devices` to find an Android device or emulator, then run
`flutter run -d <device-id>`.

The home page has a central microphone button, large Traditional Chinese text,
and suggested voice commands. Tap the microphone to grant permission and start recording; tap again to save.
The page displays elapsed time and offers playback of the latest recording.
On iOS/Android, recordings are saved as mono AAC .m4a files in the app documents
directory. Only the latest recording is retained: after a new recording saves,
previous recordings are deleted. Startup also removes older app recordings and
restores the latest clip for playback. Going to the background stops recording.
No audio is uploaded.
On iOS 16.4 or later, stopping a recording runs Breeze-ASR-26 GGML Q5 with whisper.cpp locally and shows its
Chinese transcript. A restored recording can also be transcribed manually.
The first iOS build downloads the Breeze model (1.08 GB) and runtime automatically.
Later builds reuse the local files.
On Android, the same Breeze model runs locally on LiteRT 2.3.0 (CPU, Kotlin
CompiledModel API). The 1.57 GB model is not bundled in the APK: the first
transcription downloads it once from Hugging Face into the app's external
files directory (SHA-256 verified, resumable). To skip the download during
development, push it with:

```sh
adb push breeze_asr_26_30s_i8_kv256.tflite \
  /sdcard/Android/data/com.example.an_xin_ban/files/breeze_asr_26_30s_i8_kv256.tflite
```

mel.bin, tokens.json and config.json are shared with iOS from ios/Breeze/Assets.
Android requires API 24+.
Web recordings are session-only browser blobs.

Android, iOS, and web scaffolds are included.
