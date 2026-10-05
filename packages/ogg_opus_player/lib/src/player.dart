import 'dart:io';

import 'package:flutter/foundation.dart';

import 'player_ffi_impl.dart';
import 'player_plugin_impl.dart';
import 'player_state.dart';

class OggOpusTranscription {
  const OggOpusTranscription({
    required this.text,
    required this.isFinal,
    this.duration,
  });

  factory OggOpusTranscription.fromMap(Map<Object?, Object?> map) {
    return OggOpusTranscription(
      text: map['text'] as String? ?? '',
      isFinal: map['isFinal'] as bool? ?? false,
      duration: map['duration'] as double?,
    );
  }

  final String text;
  final bool isFinal;
  final double? duration;
}

enum OggOpusSpeechAuthorizationStatus {
  authorized,
  denied,
  restricted,
  notDetermined,
  unavailable,
  unknown,
}

abstract final class OggOpusSpeechRecognizer {
  static Future<OggOpusSpeechAuthorizationStatus> authorizationStatus() {
    if (Platform.isIOS || Platform.isMacOS) {
      return speechRecognitionAuthorizationStatus();
    }
    return Future.value(OggOpusSpeechAuthorizationStatus.unavailable);
  }

  static Future<void> requestAuthorization() {
    if (Platform.isIOS || Platform.isMacOS) {
      return requestSpeechRecognitionAuthorization();
    }
    throw UnsupportedError(
        'Speech recognition is only supported on iOS and macOS');
  }

  static Future<OggOpusTranscription> transcribeFile(
    String path, {
    String? localeIdentifier,
    bool addsPunctuation = true,
  }) {
    if (Platform.isIOS || Platform.isMacOS) {
      return transcribeOggOpusFile(
        path,
        localeIdentifier: localeIdentifier,
        addsPunctuation: addsPunctuation,
      );
    }
    throw UnsupportedError(
        'Speech recognition is only supported on iOS and macOS');
  }
}

abstract class OggOpusPlayer {
  OggOpusPlayer.create();

  factory OggOpusPlayer(String path) {
    if (Platform.isIOS || Platform.isMacOS || Platform.isAndroid) {
      return OggOpusPlayerPluginImpl(path);
    } else if (Platform.isLinux || Platform.isWindows) {
      return OggOpusPlayerFfiImpl(path);
    }
    throw UnsupportedError('Platform not supported');
  }

  void pause();

  void play();

  void dispose();

  /// Seeks a local file, preserving play/pause state.
  /// Supported on Android, iOS and macOS; other platforms throw.
  Future<void> seek(Duration position) => Future.error(
      UnsupportedError('Seeking is not supported on this platform'));

  ValueListenable<PlayerState> get state;

  /// Current playing position, in seconds.
  double get currentPosition;

  /// Set playback rate, in the range 0.5 through 2.0.
  /// 1.0 is normal speed (default).
  void setPlaybackRate(double speed);
}

abstract class OggOpusRecorder {
  OggOpusRecorder.create();

  factory OggOpusRecorder(
    String path, {
    bool enableTranscription = false,
    String? transcriptionLocaleIdentifier,
    bool transcriptionAddsPunctuation = true,
  }) {
    if (Platform.isLinux || Platform.isWindows) {
      if (enableTranscription) {
        throw UnsupportedError(
            'Speech recognition is only supported on iOS and macOS');
      }
      return OggOpusRecorderFfiImpl(path);
    } else if (Platform.isIOS || Platform.isMacOS || Platform.isAndroid) {
      if (enableTranscription && !(Platform.isIOS || Platform.isMacOS)) {
        throw UnsupportedError(
            'Speech recognition is only supported on iOS and macOS');
      }
      return OggOpusRecorderPluginImpl(
        path,
        enableTranscription: enableTranscription,
        transcriptionLocaleIdentifier: transcriptionLocaleIdentifier,
        transcriptionAddsPunctuation: transcriptionAddsPunctuation,
      );
    }
    throw UnsupportedError('Platform not supported');
  }

  void start();

  Future<void> stop();

  void dispose();

  /// get the recorded audio waveform data.
  /// must be called after [stop] is called.
  Future<List<int>> getWaveformData();

  /// get the recorded audio duration.
  /// must be called after [stop] is called.
  Future<double> duration();

  Stream<OggOpusTranscription> get transcriptions;
}
