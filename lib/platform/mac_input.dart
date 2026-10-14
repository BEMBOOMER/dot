import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../core/remote_input.dart';
import '../sync/input_sink.dart';

class MacInput implements InputSink {
  static const _channel = MethodChannel('dot/input');
  final _trusted = ValueNotifier(false);
  final _textFocus = ValueNotifier(const TextFocus());
  @override
  ValueListenable<bool> get trusted => _trusted;
  @override
  ValueListenable<TextFocus> get textFocus => _textFocus;

  MacInput() {
    if (Platform.isMacOS) _channel.setMethodCallHandler(_onNativeCall);
  }

  Future<void> _onNativeCall(MethodCall call) async {
    if (call.method != 'textFocus') return;
    final args = call.arguments;
    if (args is! Map) return;
    final active = args['active'];
    final field = args['field'];
    if (active is! bool || field is! int) return;
    _textFocus.value = TextFocus(active: active, field: field);
  }

  @override
  Future<void> watchTextFocus(bool enabled) async {
    if (!enabled) _textFocus.value = const TextFocus();
    await _call('watchTextFocus', {'enabled': enabled});
  }

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
      TypedText(:final text) => _call('text', {'text': text}),
      EditKeyPress(:final key) => _call('edit', {'name': key.name}),
    };
  }

  @override
  Future<void> reset() async {
    await _call('reset');
  }
}
