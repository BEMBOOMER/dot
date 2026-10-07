import 'dart:io';

import 'package:dot/app.dart';
import 'package:dot/core/app_state.dart';
import 'package:dot/core/database.dart';
import 'package:dot/core/device_store.dart';
import 'package:dot/core/fake_sync_engine.dart';
import 'package:dot/core/item_repository.dart';
import 'package:dot/core/models.dart';
import 'package:dot/core/remote_input.dart';
import 'package:dot/core/settings_store.dart';
import 'package:dot/core/sync_engine.dart';
import 'package:dot/platform/android_remote.dart';
import 'package:dot/ui/screens/remote_screen.dart';
import 'package:dot/ui/screens/workspace_screen.dart';
import 'package:dot/ui/theme/dot_theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _RecordingEngine extends FakeSyncEngine {
  _RecordingEngine({
    required super.repository,
    required super.devices,
    super.isHost = false,
  }) : super(localDeviceId: 'phone', localName: 'Telefoon');

  final inputs = <RemoteInput>[];
  final inputStatus = ValueNotifier(
    const RemoteInputStatus(available: true, enabled: true, trusted: true),
  );
  ConnectionStatus connection = ConnectionStatus.connected;
  @override
  ConnectionStatus get status => connection;
  @override
  String get peerName => 'MacBook van Roelof';
  @override
  ValueListenable<RemoteInputStatus> get remoteStatus => inputStatus;
  @override
  void sendInput(RemoteInput input) => inputs.add(input);
  void disconnect() {
    connection = ConnectionStatus.offline;
    notifyListeners();
  }

  @override
  void dispose() {
    inputStatus.dispose();
    super.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  void remoteTest(String description, WidgetTesterCallback callback) {
    testWidgets(
      description,
      callback,
      variant: TargetPlatformVariant.only(TargetPlatform.android),
    );
  }

  sqfliteFfiInit();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late _RecordingEngine engine;
  late SettingsStore settings;
  late ItemRepository repository;
  late DeviceStore devices;
  late Database db;
  final screenCalls = <MethodCall>[];
  final volumeCalls = <MethodCall>[];
  final haptics = <String>[];
  final surface = find.byKey(const ValueKey('trackpad-surface'));

  setUp(() async {
    SharedPreferences.setMockInitialValues({'reducedMotion': true});
    settings = SettingsStore(await SharedPreferences.getInstance());
    db = await DotDatabase.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    repository = ItemRepository(db);
    devices = DeviceStore(db);
    engine = _RecordingEngine(repository: repository, devices: devices);
    screenCalls.clear();
    volumeCalls.clear();
    haptics.clear();
    messenger.setMockMethodCallHandler(AndroidRemote.screenChannel, (
      call,
    ) async {
      screenCalls.add(call);
      return null;
    });
    messenger.setMockMethodCallHandler(AndroidRemote.volumeChannel, (
      call,
    ) async {
      volumeCalls.add(call);
      return null;
    });
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate' && call.arguments is String) {
        haptics.add(call.arguments as String);
      }
      return null;
    });
  });

  tearDown(() async {
    messenger.setMockMethodCallHandler(AndroidRemote.screenChannel, null);
    messenger.setMockMethodCallHandler(AndroidRemote.volumeChannel, null);
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    engine.dispose();
    settings.dispose();
    repository.dispose();
    devices.dispose();
    await db.close();
  });

  Widget harness({
    Widget screen = const RemoteScreen(),
    ThemeMode mode = ThemeMode.light,
  }) => MultiProvider(
    providers: [
      ChangeNotifierProvider<SyncEngine>.value(value: engine),
      ChangeNotifierProvider<SettingsStore>.value(value: settings),
      ChangeNotifierProvider<ItemRepository>.value(value: repository),
    ],
    child: MaterialApp(
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: mode,
      home: screen,
      routes: {
        '/remote': (_) => const RemoteScreen(),
        '/cover': (_) => const Scaffold(body: Text('Ander scherm')),
      },
    ),
  );

  Future<void> show(
    WidgetTester tester, {
    Size size = const Size(412, 892),
    ThemeMode mode = ThemeMode.light,
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(harness(mode: mode));
    await tester.pumpAndSettle();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });
  }

  Future<void> tab(WidgetTester tester, String name) async {
    await tester.tap(find.widgetWithText(TextButton, name));
    await tester.pumpAndSettle();
  }

  Future<void> settleRepository(WidgetTester tester) async {
    await tester.pump();
    await tester.runAsync(() async {
      await repository.all();
      await Future<void>.delayed(const Duration(milliseconds: 30));
    });
    await tester.pumpAndSettle();
  }

  Future<void> volume(String direction) async {
    await messenger.handlePlatformMessage(
      AndroidRemote.volumeChannel.name,
      const StandardMethodCodec().encodeMethodCall(
        MethodCall('onVolumeKey', direction),
      ),
      (_) {},
    );
  }

  remoteTest('three tabs, peer status and light/dark phone layouts', (
    tester,
  ) async {
    await show(tester, size: const Size(320, 640));
    expect(find.text('Trackpad'), findsOneWidget);
    expect(find.text('Presentatie'), findsOneWidget);
    expect(find.text('Media'), findsOneWidget);
    expect(find.text('Verbonden met MacBook van Roelof'), findsOneWidget);
    expect(
      tester.getSize(find.widgetWithText(FilledButton, 'Links')).height,
      greaterThanOrEqualTo(56),
    );
    for (final name in ['Presentatie', 'Media', 'Trackpad']) {
      await tab(tester, name);
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(harness(mode: ThemeMode.dark));
    await tester.pumpAndSettle();
    expect(Theme.of(tester.element(surface)).brightness, Brightness.dark);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  remoteTest('single tap is one left click with haptic tick', (tester) async {
    await show(tester);
    await tester.tap(surface);
    await tester.pump(const Duration(milliseconds: 260));
    expect(engine.inputs.map((input) => input.toWire()), [
      const RemoteInput.click(RemoteButton.left).toWire(),
    ]);
    expect(haptics, contains('HapticFeedbackType.selectionClick'));
  });

  remoteTest('double tap sends count two without extra single clicks', (
    tester,
  ) async {
    await show(tester);
    await tester.tap(surface);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(surface);
    await tester.pump(const Duration(milliseconds: 300));
    expect(engine.inputs.map((input) => input.toWire()), [
      const RemoteInput.click(RemoteButton.left, count: 2).toWire(),
    ]);
  });

  remoteTest('two-finger tap sends only a right click', (tester) async {
    await show(tester);
    final center = tester.getCenter(surface);
    final first = await tester.startGesture(
      center - const Offset(20, 0),
      pointer: 1,
    );
    final second = await tester.startGesture(
      center + const Offset(20, 0),
      pointer: 2,
    );
    await first.up();
    await second.up();
    await tester.pump(const Duration(milliseconds: 400));
    expect(engine.inputs.map((input) => input.toWire()), [
      const RemoteInput.click(RemoteButton.right).toWire(),
    ]);
  });

  remoteTest('one-finger movement accumulates events into display frames', (
    tester,
  ) async {
    await show(tester);
    final gesture = await tester.startGesture(tester.getCenter(surface));
    for (var i = 0; i < 20; i++) {
      await gesture.moveBy(
        const Offset(2, 1),
        timeStamp: Duration(milliseconds: 2 * (i + 1)),
      );
    }
    expect(engine.inputs, isEmpty);
    await tester.pump(const Duration(milliseconds: 17));
    expect(engine.inputs, hasLength(1));
    final move = engine.inputs.single as PointerMove;
    expect(move.dx, greaterThan(40));
    expect(move.dy, closeTo(move.dx / 2, .01));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(engine.inputs.whereType<PointerClick>(), isEmpty);
  });

  remoteTest(
    'two fingers scroll smoothly without moving or clicking, including staggered lift',
    (tester) async {
      await show(tester);
      final center = tester.getCenter(surface);
      final first = await tester.startGesture(
        center - const Offset(20, 0),
        pointer: 1,
      );
      final second = await tester.startGesture(
        center + const Offset(20, 0),
        pointer: 2,
      );
      await first.moveBy(const Offset(0, 30));
      await second.moveBy(const Offset(0, 30));
      expect(engine.inputs, isEmpty);
      await tester.pump(const Duration(milliseconds: 17));
      expect((engine.inputs.single as PointerScroll).dy, closeTo(19.5, .01));
      await first.up();
      await second.moveBy(const Offset(20, 10));
      await second.up();
      await tester.pumpAndSettle();
      expect(engine.inputs.every((input) => input is PointerScroll), isTrue);
      expect(
        engine.inputs.cast<PointerScroll>().fold<double>(
          0,
          (total, input) => total + input.dy,
        ),
        closeTo(30, .01),
      );
    },
  );

  remoteTest('hold-drag brackets movement with down and up, haptics on start', (
    tester,
  ) async {
    await show(tester);
    final gesture = await tester.startGesture(tester.getCenter(surface));
    await tester.pump(const Duration(milliseconds: 360));
    expect((engine.inputs.single as PointerDrag).down, isTrue);
    await gesture.moveBy(const Offset(30, 0));
    await tester.pump(const Duration(milliseconds: 20));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 20));
    expect(engine.inputs.map((input) => input.runtimeType), [
      PointerDrag,
      PointerMove,
      PointerDrag,
    ]);
    expect((engine.inputs.last as PointerDrag).down, isFalse);
    expect(haptics, contains('HapticFeedbackType.lightImpact'));
  });

  remoteTest(
    'tab changes, cancellation and disposal release a held mouse button',
    (tester) async {
      await show(tester);
      var gesture = await tester.startGesture(tester.getCenter(surface));
      await tester.pump(const Duration(milliseconds: 360));
      await gesture.cancel();
      expect((engine.inputs.last as PointerDrag).down, isFalse);
      gesture = await tester.startGesture(tester.getCenter(surface));
      await tester.pump(const Duration(milliseconds: 360));
      await tab(tester, 'Presentatie');
      expect((engine.inputs.last as PointerDrag).down, isFalse);
      await gesture.up();
      await tab(tester, 'Trackpad');
      await tester.startGesture(tester.getCenter(surface));
      await tester.pump(const Duration(milliseconds: 360));
      await tester.pumpWidget(const SizedBox());
      expect((engine.inputs.last as PointerDrag).down, isFalse);
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
    },
  );

  remoteTest('presentation buttons and Android callbacks send the right keys', (
    tester,
  ) async {
    await show(tester);
    await volume('next');
    expect(engine.inputs, isEmpty);
    await tab(tester, 'Presentatie');
    expect(screenCalls.last.arguments, isTrue);
    expect(volumeCalls.last.arguments, isTrue);
    for (final label in [
      'Volgende',
      'Vorige',
      'Start',
      'Keynote starten',
      'Zwart scherm',
      'Stop',
    ]) {
      await tester.tap(find.widgetWithText(FilledButton, label));
    }
    await volume('next');
    await volume('prev');
    expect(engine.inputs.cast<PresentationKey>().map((input) => input.key), [
      RemoteKey.next,
      RemoteKey.prev,
      RemoteKey.start,
      RemoteKey.startKeynote,
      RemoteKey.blackout,
      RemoteKey.end,
      RemoteKey.next,
      RemoteKey.prev,
    ]);
    await tab(tester, 'Media');
    expect(screenCalls.last.arguments, isFalse);
    expect(volumeCalls.last.arguments, isFalse);
    await volume('next');
    expect(engine.inputs, hasLength(8));
  });

  remoteTest(
    'background and covering routes disable native shortcuts; resume restores them',
    (tester) async {
      await show(tester);
      await tab(tester, 'Presentatie');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(volumeCalls.last.arguments, isFalse);
      expect(screenCalls.last.arguments, isFalse);
      await volume('next');
      expect(engine.inputs, isEmpty);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(volumeCalls.last.arguments, isTrue);
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      navigator.pushNamed('/cover');
      await tester.pumpAndSettle();
      expect(volumeCalls.last.arguments, isFalse);
      navigator.pop();
      await tester.pumpAndSettle();
      expect(volumeCalls.last.arguments, isTrue);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(volumeCalls.last.arguments, isFalse);
      expect(screenCalls.last.arguments, isFalse);
    },
  );

  remoteTest('timer starts, pauses, resets and leaves no background timers', (
    tester,
  ) async {
    await show(tester);
    await tab(tester, 'Presentatie');
    final timer = find.byKey(const ValueKey('slide-timer'));
    expect(find.text('00:00'), findsOneWidget);
    await tester.tap(timer);
    await tester.pump();
    expect(find.text('Tik om te pauzeren'), findsOneWidget);
    await tester.tap(timer);
    await tester.pump();
    expect(find.text('Tik om te starten'), findsOneWidget);
    await tester.tap(timer);
    await tester.pump();
    await tester.longPress(timer);
    await tester.pump();
    expect(find.text('00:00'), findsOneWidget);
    expect(find.text('Tik om te starten'), findsOneWidget);
    await tester.tap(timer);
    await tester.pump();
    await tab(tester, 'Trackpad');
    await tester.pump(const Duration(seconds: 2));
    await tab(tester, 'Presentatie');
    expect(find.text('Tik om te starten'), findsOneWidget);
    await tester.tap(timer);
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
  });

  remoteTest('live trust and disabled banners gate every kind of input', (
    tester,
  ) async {
    engine.inputStatus.value = const RemoteInputStatus(
      available: true,
      enabled: true,
    );
    await show(tester);
    expect(
      find.text(
        'Geef DOT op je Mac toegang: Systeeminstellingen > Privacy en beveiliging > Toegankelijkheid.',
      ),
      findsOneWidget,
    );
    await tester.tap(surface);
    await tester.pump(const Duration(milliseconds: 400));
    expect(engine.inputs, isEmpty);
    engine.inputStatus.value = const RemoteInputStatus(
      available: true,
      trusted: true,
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Bediening op afstand staat uit op je Mac.'),
      findsOneWidget,
    );
    expect(find.textContaining('Geef DOT'), findsNothing);
    engine.inputStatus.value = const RemoteInputStatus(
      available: true,
      trusted: true,
      enabled: true,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Links'));
    expect(engine.inputs.single, isA<PointerClick>());
    engine.disconnect();
    await tester.pumpAndSettle();
    await tab(tester, 'Presentatie');
    await volume('next');
    expect(engine.inputs, hasLength(1));
  });

  remoteTest('media grid sends all six commands', (tester) async {
    await show(tester);
    await tab(tester, 'Media');
    for (final label in [
      'Vorige',
      'Afspelen of pauzeren',
      'Volgende',
      'Zachter',
      'Dempen',
      'Harder',
    ]) {
      await tester.tap(find.byTooltip(label));
    }
    expect(engine.inputs.cast<MediaKey>().map((input) => input.media), [
      RemoteMedia.prev,
      RemoteMedia.playpause,
      RemoteMedia.next,
      RemoteMedia.voldown,
      RemoteMedia.mute,
      RemoteMedia.volup,
    ]);
  });

  remoteTest('speed sheet persists and validates the trackpad preference', (
    tester,
  ) async {
    await show(tester);
    expect(settings.trackpadSpeed, 1);
    await tester.tap(find.byTooltip('Trackpadinstellingen'));
    await tester.pumpAndSettle();
    tester.widget<Slider>(find.byType(Slider)).onChanged!(1.8);
    await tester.pump();
    expect(SettingsStore(settings.prefs).trackpadSpeed, 1.8);
    settings.trackpadSpeed = double.nan;
    expect(settings.trackpadSpeed, 1.8);
    settings.trackpadSpeed = 9;
    expect(settings.trackpadSpeed, 2.5);
  });

  remoteTest(
    'workspace entry is client-only, disabled offline and routes to remote',
    (tester) async {
      await show(tester);
      await tester.pumpWidget(harness(screen: const WorkspaceScreen()));
      await settleRepository(tester);
      expect(find.text('Bediening'), findsOneWidget);
      await tester.tap(find.text('Bediening'));
      await settleRepository(tester);
      expect(find.byType(RemoteScreen), findsOneWidget);
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await settleRepository(tester);
      engine.disconnect();
      await settleRepository(tester);
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Bediening'))
            .onPressed,
        isNull,
      );
      await tester.pumpWidget(const SizedBox());
      engine.dispose();
      engine = _RecordingEngine(
        repository: repository,
        devices: devices,
        isHost: true,
      );
      await tester.pumpWidget(harness(screen: const WorkspaceScreen()));
      await settleRepository(tester);
      expect(find.text('Bediening'), findsNothing);
    },
  );

  remoteTest(
    'Eerst bekijken uses the real no-op FakeSyncEngine through the app route',
    (tester) async {
      await show(tester);
      await tester.pumpWidget(const SizedBox());
      databaseFactory = databaseFactoryFfi;
      final directory = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('dot-remote-demo-'),
      ))!;
      final state = AppState(
        repository: repository,
        devices: devices,
        settings: settings,
        engine: engine,
        supportDirectory: directory,
      );
      // DotApp owns these stores, so give tearDown fresh ones after this test.
      await tester.pumpWidget(DotApp(state: state));
      await tester.runAsync(() async {
        await tester.tap(find.text('Eerst bekijken'));
        await Future.doWhile(() async {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          return !state.isDemoMode ||
              state.engine.status != ConnectionStatus.connected;
        }).timeout(const Duration(seconds: 5));
      });
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bediening'));
      await tester.pumpAndSettle();
      expect(find.byType(RemoteScreen), findsOneWidget);
      expect(find.text('Voorbeeldbediening'), findsOneWidget);
      expect(find.textContaining('Geef DOT'), findsNothing);
      await tester.tap(find.widgetWithText(FilledButton, 'Links'));
      await tab(tester, 'Presentatie');
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Volgende'))
            .onPressed,
        isNotNull,
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Volgende'));
      expect(engine.inputs, isEmpty);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      await tester.runAsync(() async {
        await directory.delete(recursive: true);
        settings = SettingsStore(await SharedPreferences.getInstance());
        db = await DotDatabase.open(
          factory: databaseFactoryFfi,
          path: inMemoryDatabasePath,
        );
        repository = ItemRepository(db);
        devices = DeviceStore(db);
        engine = _RecordingEngine(repository: repository, devices: devices);
      });
    },
  );
}
