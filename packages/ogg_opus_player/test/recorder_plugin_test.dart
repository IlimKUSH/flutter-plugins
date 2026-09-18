import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogg_opus_player/src/player_plugin_impl.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('ogg_opus_player');
  const codec = StandardMethodCodec();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  Future<void> sendRecorderFinished(int id) async {
    final reply = Completer<ByteData?>();
    messenger.handlePlatformMessage(
      channel.name,
      codec.encodeMethodCall(
        MethodCall('onRecorderFinished', {
          'recorderId': id,
          'duration': 1200,
          'waveform': <int>[1, 2, 3],
        }),
      ),
      reply.complete,
    );
    await reply.future;
  }

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test(
    'recorder sends a path map and completes start, stop, and dispose',
    () async {
      final calls = <MethodCall>[];
      final destroyed = Completer<void>();
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        switch (call.method) {
          case 'createRecorder':
            return 1;
          case 'stopRecord':
            await sendRecorderFinished(call.arguments as int);
            return null;
          case 'destroyRecorder':
            destroyed.complete();
            return null;
        }
        return null;
      });

      final recorder = OggOpusRecorderPluginImpl(
        '/tmp/recorded.ogg',
        enableTranscription: false,
        transcriptionAddsPunctuation: true,
      );
      await recorder.start();
      await recorder.stop();
      expect(await recorder.duration(), 1.2);
      expect(await recorder.getWaveformData(), [1, 2, 3]);
      recorder.dispose();
      await destroyed.future;

      expect(calls.map((call) => call.method), [
        'createRecorder',
        'startRecord',
        'stopRecord',
        'destroyRecorder',
      ]);
      expect(calls.first.arguments, containsPair('path', '/tmp/recorded.ogg'));
      expect(calls.skip(1).map((call) => call.arguments), [1, 1, 1]);
    },
  );
}
