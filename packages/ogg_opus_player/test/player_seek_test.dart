import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogg_opus_player/ogg_opus_player.dart';
import 'package:ogg_opus_player/src/player_plugin_impl.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('ogg_opus_player');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('seek waits for creation and reports the actual clamped native position',
      () async {
    final directory = Directory.systemTemp.createTempSync('opus-seek-');
    final file = File('${directory.path}/voice.ogg')..writeAsBytesSync([]);
    addTearDown(() => directory.deleteSync(recursive: true));
    final created = Completer<int>();
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'create') return created.future;
      if (call.method == 'seek') return 1.25;
      return null;
    });
    final player = OggOpusPlayerPluginImpl(file.path);
    final seeking = player.seek(const Duration(seconds: 20));
    await Future<void>.delayed(Duration.zero);
    expect(calls.map((call) => call.method), ['create']);
    created.complete(7);
    await seeking;
    expect(calls.last.arguments, {'playerId': 7, 'position': 20.0});
    expect(player.currentPosition, 1.25);
    expect(player.state.value, PlayerState.paused);
    player.dispose();
  });

  test('negative seek is clamped and channel failures reach the caller',
      () async {
    final directory = Directory.systemTemp.createTempSync('opus-seek-');
    final file = File('${directory.path}/voice.ogg')..writeAsBytesSync([]);
    addTearDown(() => directory.deleteSync(recursive: true));
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'create') return 8;
      if (call.method == 'seek') throw PlatformException(code: 'seek_failed');
      return null;
    });
    final player = OggOpusPlayerPluginImpl(file.path);
    await expectLater(player.seek(const Duration(seconds: -1)),
        throwsA(isA<PlatformException>()));
    expect(calls.last.arguments, {'playerId': 8, 'position': 0.0});
    player.dispose();
  });
}
