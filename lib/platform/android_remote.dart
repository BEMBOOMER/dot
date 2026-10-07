import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../core/remote_input.dart';

/// Owns Android presentation shortcuts for the lifetime of the remote screen.
class AndroidRemote {
  static const screenChannel = MethodChannel('dot/screen');
  static const volumeChannel = MethodChannel('dot/volume_keys');

  final void Function(RemoteKey key) onVolumeKey;
  bool _active = false;
  bool _disposed = false;

  AndroidRemote({required this.onVolumeKey}) {
    if (_supported) volumeChannel.setMethodCallHandler(_onCall);
  }

  bool get _supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<void> _onCall(MethodCall call) async {
    if (!_active || _disposed || call.method != 'onVolumeKey') return;
    switch (call.arguments) {
      case 'next':
        onVolumeKey(RemoteKey.next);
      case 'prev':
        onVolumeKey(RemoteKey.prev);
    }
  }

  Future<void> setPresentationActive(bool active) async {
    if (_disposed || !_supported) return;
    _active = active;
    await Future.wait([
      _invoke(screenChannel, 'setKeepAwake', active),
      _invoke(volumeChannel, 'setEnabled', active),
    ]);
  }

  Future<void> _invoke(MethodChannel channel, String method, bool value) async {
    try {
      await channel.invokeMethod<void>(method, value);
    } on MissingPluginException {
      // Non-native previews can still render every control.
    } on PlatformException {
      // Shortcuts are optional; on-screen controls remain usable.
    }
  }

  void dispose() {
    if (_disposed) return;
    unawaited(setPresentationActive(false));
    _disposed = true;
    _active = false;
    if (_supported) volumeChannel.setMethodCallHandler(null);
  }
}
