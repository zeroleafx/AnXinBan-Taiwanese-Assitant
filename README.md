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
| 打開相機、打開相簿、開 Instagram | Android: any installed app, by the name under its icon. iOS: a short list of apps with a known link |
| 打電話予阿明、打給女兒、給阿明打電話 | Finds the name in Contacts; asks which one if several match; dials |
| 打 119、撥零九一二…、叫救護車、報警 | Dials the spoken number, 119 or 110 |
| 救命、我跌倒了 | Calls the emergency contact and shows the help card (also behind the SOS button, which calls no one by itself): call the contact, call 119, send the location |
| 把女兒設成緊急聯絡人、設定緊急聯絡人、取消緊急聯絡人 | Chooses who is called first in an emergency; saved on the phone |
| 我在哪裡 | Shows the street address, with a button to open the map |
| 把我的位置傳給女兒、分享我的位置、用 LINE 傳我的位置 | Opens a text message to that contact (or LINE's "share with" screen) with the address and a map link filled in |
| 傳簡訊給阿明說我晚一點到、用 LINE 跟女兒說我到了 | Opens the message with the words filled in |
| 開手電筒、手電筒關掉、手電筒禁掉；開著時只講「關掉」 | Turns the flashlight on or off; just 「手電筒」 switches it over. While it is on, an off button stays on screen |
| 帶我去台北車站、郵局在哪裡 | Opens directions in Google Maps (Apple Maps if not installed) |
| 我想聽鄧麗君的歌 | Searches YouTube |
| 現在幾點、今天禮拜幾、今天農曆幾號、今天會下雨嗎 | Shows the time, the date or the lunar date; opens a weather search |

The flashlight goes through the app's own channel `anxinban/torch`
(`ios/Runner/AppDelegate.swift`, `android/.../TorchControl.kt`) rather than a
plugin, so the app can also read whether the light is on. When the app comes
back to the front it checks, so switching the light off from the control
centre also updates the screen. On iOS the app also stops asking for the
light once it goes dark outside the app or the app leaves the screen;
otherwise iOS lights it again when the app comes back.

iOS always asks before placing a call; Android opens the dialer with the
number filled in. Messages are only written: the person presses send.
Calling by name needs the Contacts permission
(`NSContactsUsageDescription` on iOS, `READ_CONTACTS` on Android); contacts
are read on the phone only. The location is read only when one of the
commands above asks for it (`NSLocationWhenInUseUsageDescription` on iOS,
`ACCESS_FINE_LOCATION` and `ACCESS_COARSE_LOCATION` on Android); the phone's
own geocoder turns it into an address.

## Speech model download (Android)

When the Android build offers the `modelStatus` and `downloadModel` channel
methods, the app asks before downloading the speech model: it shows the size,
warns when the phone is not on Wi-Fi, shows progress, and continues an
interrupted download. Users can defer setup to record without transcription.
Android builds without these methods still download during the first
transcription.
On iOS/Android, recordings are saved as mono AAC .m4a files in the app documents
directory. Only the latest recording is retained: after a new recording saves,
previous recordings are deleted. Startup also removes older app recordings and
restores the latest clip for playback. Going to the background stops recording.
Mobile recognition runs on-device. On web, recording and playback stay local until the user selects the upload button.
On iOS 16.4 or later, stopping a recording runs Breeze-ASR-26 GGML Q5 with whisper.cpp locally and shows its
Chinese transcript. A restored recording can also be transcribed manually.
The iOS build prepares the whisper.cpp runtime. On both iOS and Android,
the app checks for the model at startup. If missing, it offers to download it
with progress, resume and SHA-256 verification: GGML Q5 (1.08 GB) on iOS, the
int8 LiteRT model (1.57 GB) on Android. Users can defer the download and record
or play audio without transcription. Subsequent recordings work offline.
Android runs Breeze-ASR-26 on LiteRT 2.3.0 (CPU, Kotlin CompiledModel API)
rather than GGML Q5, because whisper.cpp's fast ARM kernels cover Q4_0/Q8_0
but not Q5, so Q5 is much slower there.
To preload an Android device during development:

```sh
adb shell mkdir -p /sdcard/Android/data/com.example.an_xin_ban/files
adb push breeze_asr_26_30s_i8_kv256.tflite /sdcard/Android/data/com.example.an_xin_ban/files/
```

Android requires API 24+.
Web recordings are session-only browser blobs.

Android, iOS, and web scaffolds are included.


### Web transcription on Hugging Face Spaces

Deploy the contents of `space/` to a Docker Space on CPU Basic.
Use its HTTPS app URL when building the Flutter web app:

```sh
flutter build web --dart-define=BREEZE_SPACE_URL=https://YOUR-SPACE.hf.space
```

With no URL configured, web remains recording/playback only.
