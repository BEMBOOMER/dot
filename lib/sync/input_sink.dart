import 'package:flutter/foundation.dart';

import '../core/remote_input.dart';

/// Host execution boundary. Implementations must recheck native trust and
/// complete quickly. A failed dispatch must not throw into the sync session.
abstract interface class InputSink {
  ValueListenable<bool> get trusted;
  Future<void> refreshTrust();
  Future<bool> dispatch(RemoteInput input);

  /// Release a held mouse button on disconnect, revocation or disabling input.
  Future<void> reset();

  /// Whether a text field on this computer has keyboard focus. Only updated
  /// while watching is enabled; reads inactive otherwise.
  ValueListenable<TextFocus> get textFocus;

  /// Start or stop watching text focus. The engine enables this only while a
  /// trusted, paired phone is connected and remote control is on.
  Future<void> watchTextFocus(bool enabled);
}
