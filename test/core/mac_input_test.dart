import 'dart:io';

import 'package:dot/core/remote_input.dart';
import 'package:dot/platform/mac_input.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dot/input');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test(
    'MacInput uses the native channel for trust and all input kinds',
    () async {
      final calls = <MethodCall>[];
      var trusted = true;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return call.method == 'isTrusted' ? trusted : true;
      });
      final input = MacInput();
      await input.refreshTrust();
      expect(input.trusted.value, isTrue);
      final commands = <RemoteInput>[
        const RemoteInput.move(9000, -9000),
        const RemoteInput.click(RemoteButton.right, count: 2),
        const RemoteInput.drag(down: true),
        const RemoteInput.scroll(1, -2),
        const RemoteInput.key(RemoteKey.startKeynote),
        const RemoteInput.media(RemoteMedia.playpause),
      ];
      for (final command in commands) {
        expect(await input.dispatch(command), isTrue);
      }
      expect(calls.skip(1).map((c) => c.method), [
        'move',
        'click',
        'drag',
        'scroll',
        'key',
        'media',
      ]);
      expect(calls[1].arguments, {'dx': 2000.0, 'dy': -2000.0});
      expect(calls[2].arguments, {'button': 'right', 'count': 2});
      expect(calls[5].arguments, {'name': 'start_keynote'});
      await MacInput.requestTrust();
      await MacInput.openAccessibilitySettings();
      await input.reset();
      expect(calls.skip(7).map((c) => c.method), [
        'requestTrust',
        'openAccessibilitySettings',
        'reset',
      ]);
      trusted = false;
      await input.refreshTrust();
      expect(input.trusted.value, isFalse);
    },
    skip: !Platform.isMacOS,
  );

  test('missing native plugin fails closed without throwing', () async {
    final input = MacInput();
    await input.refreshTrust();
    expect(input.trusted.value, isFalse);
    expect(await input.dispatch(const RemoteInput.move(1, 2)), isFalse);
    expect(await MacInput.requestTrust(), isFalse);
    await input.reset();
  });
}
