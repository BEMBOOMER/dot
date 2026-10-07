import 'dart:async';
import 'dart:io';

import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import '../core/app_state.dart';

class ShareIntake {
  ShareIntake._();

  static StreamSubscription<List<SharedMediaFile>>? _subscription;

  static Future<void> init(AppState state) async {
    if (!Platform.isAndroid) return;
    final initial = await ReceiveSharingIntent.instance.getInitialMedia();
    await _consume(initial, state);
    _subscription?.cancel();
    _subscription = ReceiveSharingIntent.instance.getMediaStream().listen(
      (files) => _consume(files, state),
      onError: (Object error, StackTrace stack) {},
    );
  }

  static Future<void> _consume(
    List<SharedMediaFile> files,
    AppState state,
  ) async {
    for (final file in files) {
      final path = file.path;
      if (path.isNotEmpty && File(path).existsSync()) {
        await state.addFile(path);
        continue;
      }
      final message = file.message?.trim();
      if (message == null || message.isEmpty) continue;
      if (RegExp(r'^https?://', caseSensitive: false).hasMatch(message)) {
        await state.addLink(message);
      } else {
        await state.addText(message);
      }
    }
    ReceiveSharingIntent.instance.reset();
  }

  static Future<void> dispose() async => _subscription?.cancel();
}
