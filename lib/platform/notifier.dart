import 'dart:async';
import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../core/app_state.dart';
import '../core/models.dart';

class DotNotifier {
  DotNotifier._();

  static final _plugin = FlutterLocalNotificationsPlugin();
  static StreamSubscription<SyncEvent>? _subscription;
  static Future<void>? _permissionRequest;

  static Future<void> init(AppState state) async {
    if (!Platform.isAndroid && !Platform.isMacOS) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwin = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _plugin.initialize(
      settings: const InitializationSettings(android: android, macOS: darwin),
    );
    await _subscription?.cancel();
    _subscription = state.engine.events.listen((event) async {
      if (!state.settings.notifications ||
          (event is! PairedEvent && event is! ItemReceivedEvent)) {
        return;
      }
      await (_permissionRequest ??= _requestPermission());
      if (event is! ItemReceivedEvent) return;
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

  static Future<void> _requestPermission() async {
    if (Platform.isAndroid) {
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
    } else if (Platform.isMacOS) {
      await _plugin
          .resolvePlatformSpecificImplementation<
            MacOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    }
  }

  static Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
  }
}
