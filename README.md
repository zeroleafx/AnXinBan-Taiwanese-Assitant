# 安心BAN · AnXinBan

A Flutter home-page prototype for a Taiwanese-language voice assistant.

## Run

```sh
flutter pub get
flutter run -d chrome
```

Use `flutter devices` to find an Android device or emulator, then run
`flutter run -d <device-id>`.

The home page fits one portrait screen without scrolling: a large microphone
button, one short line of status text, and a card that shows example commands
or the result of the last request. Tap the microphone to grant permission and
start recording; tap again to save. The page shows the elapsed time while
recording, and the result card can play the latest recording back.

## Voice commands

After Breeze transcribes a recording, `lib/voice_command.dart` turns the text
into a phone action and `lib/phone_actions.dart` performs it:

| Say (examples) | What happens |
|---|---|
| 幫我開 LINE、開 YouTube、上臉書、開地圖、看簡訊 | Opens the app (or says it is not installed) |
| 打電話予阿明、打給女兒、給阿明打電話 | Finds the name in Contacts; asks which one if several match; dials |
| 打 119、撥零九一二… | Dials the spoken number |
| 開手電筒、手電筒關掉 | Turns the flashlight on or off (with a one-tap off button) |
| 帶我去台北車站、郵局在哪裡 | Opens directions in Google Maps (Apple Maps if not installed) |
| 我想聽鄧麗君的歌 | Searches YouTube |
| 現在幾點、今天禮拜幾、今天會下雨嗎 | Shows the time or date; opens a weather search |

iOS always asks before placing a call; Android opens the dialer with the
number filled in. Calling by name needs the Contacts permission
(`NSContactsUsageDescription` on iOS, `READ_CONTACTS` on Android); contacts
are read on the phone only.
On iOS/Android, recordings are saved as mono AAC .m4a files in the app documents
directory. Only the latest recording is retained: after a new recording saves,
previous recordings are deleted. Startup also removes older app recordings and
restores the latest clip for playback. Going to the background stops recording.
No audio is uploaded.
On iOS 16.4 or later, stopping a recording runs Breeze-ASR-26 GGML Q5 with whisper.cpp locally and shows its
Chinese transcript. A restored recording can also be transcribed manually.
The iOS build prepares the whisper.cpp runtime. On both iOS and Android,
the app checks for the model at startup. If missing, it offers a 1.08 GB
download with progress, resume and SHA-256 verification. Users can defer
the download and record or play audio without transcription.
Subsequent recordings work offline. The Android build downloads the pinned
whisper.cpp source and compiles the CPU runtime with the NDK.
To preload a device during development:

```sh
adb shell mkdir -p /sdcard/Android/data/com.example.an_xin_ban/files
adb push ios/Breeze/.build/ggml-model-q5_0.bin /sdcard/Android/data/com.example.an_xin_ban/files/
```

Android requires API 24+.
Web recordings are session-only browser blobs.

Android, iOS, and web scaffolds are included.
