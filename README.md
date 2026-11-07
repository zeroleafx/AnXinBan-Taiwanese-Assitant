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
On iPhone, stopping a recording runs Breeze-ASR-26-LiteRT locally and shows its
Chinese transcript. A restored recording can also be transcribed manually.
Before the first iOS build from a fresh checkout, run
`./tool/prepare_breeze_ios.sh` to download the model (1.57 GB) and iOS runtime.
Web recordings are session-only browser blobs.

Android, iOS, and web scaffolds are included.
