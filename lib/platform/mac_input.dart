import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../core/remote_input.dart';
import '../sync/input_sink.dart';

class MacInput implements InputSink {
  static const _channel = MethodChannel('dot/input');
  final _trusted = ValueNotifier(false);
  @override
  ValueListenable<bool> get trusted => _trusted;

  static Future<bool> _call(String method, [Object? arguments]) async {
    if (!Platform.isMacOS) return false;
    try {
      return await _channel
              .invokeMethod<bool>(method, arguments)
              .timeout(const Duration(seconds: 1), onTimeout: () => false) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  static Future<bool> isTrusted() => _call('isTrusted');
  static Future<bool> requestTrust() => _call('requestTrust');
  static Future<bool> openAccessibilitySettings() =>
      _call('openAccessibilitySettings');

  @override
  Future<void> refreshTrust() async {
    _trusted.value = await isTrusted();
  }

  @override
  Future<bool> dispatch(RemoteInput input) {
    final wire = input.toWire();
    if (RemoteInput.fromWire(wire) == null) return Future.value(false);
    return switch (input) {
      PointerMove() => _call('move', {'dx': wire['dx'], 'dy': wire['dy']}),
      PointerClick(:final button, :final count) => _call('click', {
        'button': button.name,
        'count': count,
      }),
      PointerDrag(:final down) => _call('drag', {'s': down ? 'down' : 'up'}),
      PointerScroll() => _call('scroll', {'dx': wire['dx'], 'dy': wire['dy']}),
      PresentationKey(:final key) => _call('key', {'name': key.wireName}),
      MediaKey(:final media) => _call('media', {'name': media.name}),
    };
  }

  @override
  Future<void> reset() async {
    await _call('reset');
  }
}
