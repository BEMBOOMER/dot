import 'dart:async';
import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../core/app_state.dart';
import '../core/models.dart';

class DotNotifier {
  DotNotifier._();

  static final _plugin = FlutterLocalNotificationsPlugin();
  static StreamSubscription<SyncEvent>? _subscription;

  static Future<void> init(AppState state) async {
    if (!Platform.isAndroid && !Platform.isMacOS) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwin = DarwinInitializationSettings();
    await _plugin.initialize(
      settings: const InitializationSettings(android: android, macOS: darwin),
    );
    if (Platform.isAndroid) {
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
    }
    await _subscription?.cancel();
    _subscription = state.engine.events.listen((event) async {
      if (!state.settings.notifications || event is! ItemReceivedEvent) {
        return;
      }
      await _plugin.show(
        id: event.itemId.hashCode,
        title: 'Nieuw item in DOT',
        body: 'Er is iets nieuws ontvangen.',
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'dot_received',
            'Ontvangen items',
            channelDescription: 'Meldingen voor ontvangen items',
            importance: Importance.defaultImportance,
          ),
          macOS: DarwinNotificationDetails(),
        ),
      );
    });
  }

  static Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
  }
}
