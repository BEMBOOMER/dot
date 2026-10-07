import 'dart:convert';

import 'package:dot/core/remote_input.dart';
import 'package:dot/core/settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('every input round-trips through JSON with its exact fields', () {
    final inputs = <RemoteInput>[
      const RemoteInput.move(12.5, -24),
      const RemoteInput.scroll(-2, 3.75),
      for (final button in RemoteButton.values)
        for (final count in [1, 2]) RemoteInput.click(button, count: count),
      const RemoteInput.drag(down: true),
      const RemoteInput.drag(down: false),
      for (final key in RemoteKey.values) RemoteInput.key(key),
      for (final media in RemoteMedia.values) RemoteInput.media(media),
    ];
    for (final input in inputs) {
      final restored = RemoteInput.fromWire(
        jsonDecode(jsonEncode(input.toWire())),
      );
      expect(restored.runtimeType, input.runtimeType);
      expect(restored!.toWire(), input.toWire());
    }
    expect(
      const RemoteInput.key(RemoteKey.startKeynote).toWire()['key'],
      'start_keynote',
    );
    expect(const RemoteInput.click(RemoteButton.left).toWire()['n'], 1);
  });

  test('outgoing deltas clamp, incoming oversized deltas are dropped', () {
    for (final input in [
      const RemoteInput.move(3000, -4000),
      const RemoteInput.scroll(1e100, -1e100),
    ]) {
      expect(input.toWire()['dx'], 2000);
      expect(input.toWire()['dy'], -2000);
      expect(RemoteInput.fromWire(input.toWire()), isNotNull);
    }
    for (final kind in ['move', 'scroll']) {
      expect(
        RemoteInput.fromWire({'t': 'input', 'k': kind, 'dx': 2000.01, 'dy': 0}),
        isNull,
      );
      expect(
        RemoteInput.fromWire({'t': 'input', 'k': kind, 'dx': 0, 'dy': -2001}),
        isNull,
      );
      expect(
        RemoteInput.fromWire({
          't': 'input',
          'k': kind,
          'dx': 2000,
          'dy': -2000,
        }),
        isNotNull,
      );
    }
  });

  test('malformed, non-finite, extra and unknown fields are dropped', () {
    final invalid = <Object?>[
      null,
      [],
      'input',
      {},
      {'t': 'other', 'k': 'key', 'key': 'space'},
      {'t': 'input', 'k': 'launch', 'command': 'anything'},
      {'t': 'input', 'k': 'move', 'dx': 0},
      for (final value in [
        '1',
        true,
        null,
        double.nan,
        double.infinity,
        -double.infinity,
      ])
        for (final kind in ['move', 'scroll'])
          {'t': 'input', 'k': kind, 'dx': value, 'dy': 0},
      {'t': 'input', 'k': 'move', 'dx': 0, 'dy': 0, 'extra': 'x' * 10000},
      for (final count in [0, 3, -1, 1.0, '1', true, null])
        {'t': 'input', 'k': 'click', 'b': 'left', 'n': count},
      {'t': 'input', 'k': 'click', 'b': 'middle', 'n': 1},
      {'t': 'input', 'k': 'drag', 's': true},
      {'t': 'input', 'k': 'drag', 's': 'cancel'},
      {'t': 'input', 'k': 'key', 'key': 'enter'},
      {'t': 'input', 'k': 'media', 'm': 'stop'},
    ];
    for (final wire in invalid) {
      expect(RemoteInput.fromWire(wire), isNull);
    }
  });

  test(
    'status strictly validates booleans and advertises capability locally',
    () {
      const state = RemoteInputStatus(
        enabled: true,
        trusted: false,
        available: true,
      );
      expect(
        RemoteInputStatus.fromWire(jsonDecode(jsonEncode(state.toWire()))),
        state,
      );
      expect(state.toWire().containsKey('available'), isFalse);
      for (final wire in [
        null,
        {},
        {'t': 'input_status', 'enabled': 1, 'trusted': false},
        {'t': 'input_status', 'enabled': true, 'trusted': 'false'},
        {'t': 'input_status', 'enabled': true},
        {'t': 'input_status', 'enabled': true, 'trusted': true, 'extra': 1},
      ]) {
        expect(RemoteInputStatus.fromWire(wire), isNull);
      }
    },
  );

  test('remote control defaults on and persists explicit opt-out', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final settings = SettingsStore(prefs);
    expect(settings.remoteControl, isTrue);
    settings.remoteControl = false;
    final restarted = SettingsStore(prefs);
    expect(restarted.remoteControl, isFalse);
    settings.dispose();
    restarted.dispose();
  });
}
