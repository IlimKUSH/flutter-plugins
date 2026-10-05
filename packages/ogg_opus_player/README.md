# ogg_opus_player

[![Pub](https://img.shields.io/pub/v/ogg_opus_player.svg)](https://pub.dev/packages/ogg_opus_player)

a ogg opus file player for flutter.

| platform |   | required os version |
|----------|---|---------------------|
| iOS      | ✅ | 13.0                |
| macOS    | ✅ | 10.15               |
| Windows  | ✅ |                     |
| Linux    | ✅ |                     |
| Android  | ✅ | minSdk 21           |

## Getting Started

1. add `ogg_opus_player` to your pubspec.yaml

    ```yaml
      ogg_opus_player: $latest_version
    ```

2. then you can play your opus ogg file from `OggOpusPlayer`

    ```dart
    import 'package:ogg_opus_player/ogg_opus_player.dart';
    
    void playOggOpusFile() {
      final player = OggOpusPlayer("file_path");
    
      player.play();
      player.pause();
    
      player.dipose();
    }
    ```

## AudioSession

For android/iOS platform, you need to manage audio session by yourself.

It is recommended to use [audio_session](https://pub.dev/packages/audio_session) to manage audio session.

## Speech recognition

Speech recognition is currently only supported on iOS 10.0 or later and macOS 10.15 or later.

```dart
final status = await OggOpusSpeechRecognizer.authorizationStatus();
await OggOpusSpeechRecognizer.requestAuthorization();

final transcription = await OggOpusSpeechRecognizer.transcribeFile(
  'file_path.ogg',
  localeIdentifier:
      WidgetsBinding.instance.platformDispatcher.locale.toLanguageTag(),
);
print(transcription.text);
```

For live recording transcription, enable transcription when creating the recorder:

```dart
final recorder = OggOpusRecorder(
  'file_path.ogg',
  enableTranscription: true,
  transcriptionLocaleIdentifier:
      WidgetsBinding.instance.platformDispatcher.locale.toLanguageTag(),
);

final subscription = recorder.transcriptions.listen((transcription) {
  print(transcription.text);
});

recorder.start();
```

On macOS, requesting speech recognition permission from Flutter tooling or VS Code can crash before Dart
receives an error. Start the app from Xcode when granting speech recognition permission for the first time.

## Linux required

Need SDL2 library installed on Linux.

```shell
sudo apt-get install libsdl2-dev
sudo apt-get install libopus-dev
```

## iOS/macOS required

Record voice need update your app's Info.plist NSMicrophoneUsageDescription key with a string value
explaining to the user how the app uses this data.

For example:

```
    <key>NSMicrophoneUsageDescription</key>
    <string>Example uses your microphone to record voice for test.</string>
```

Speech recognition also requires `NSSpeechRecognitionUsageDescription`:

```
    <key>NSSpeechRecognitionUsageDescription</key>
    <string>Example uses speech recognition to transcribe recorded voice.</string>
```

for macOS, you also need update your `DebugProfile.entitlements` and `ReleaseProfile.entitlements` with the following:

```
    <key>com.apple.security.device.microphone</key>
    <true/>
    <key>com.apple.security.device.audio-input</key>
    <true/>
    <key>com.apple.security.network.client</key>
    <true/>
```

## LICENSE

see LICENSE file

### Seeking local voice files

On Android, iOS and macOS, `await player.seek(Duration(seconds: 12))` changes
the position without changing play/pause state. Negative positions are clamped
to zero and positions beyond the file duration are clamped to its end.
`currentPosition` reports the selected position in seconds after completion.
Windows and Linux currently throw `UnsupportedError` for seeking.
