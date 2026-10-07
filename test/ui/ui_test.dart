import 'dart:io';

import 'package:file_picker/file_picker.dart';

import 'package:dot/app.dart';
import 'package:dot/core/app_state.dart';
import 'package:dot/core/database.dart';
import 'package:dot/core/device_store.dart';
import 'package:dot/core/fake_sync_engine.dart';
import 'package:dot/core/item_repository.dart';
import 'package:dot/core/models.dart';
import 'package:dot/core/settings_store.dart';
import 'package:dot/core/sync_engine.dart';
import 'package:dot/ui/dots/dots_stage.dart';
import 'package:dot/ui/theme/dot_theme.dart';
import 'package:dot/ui/screens/item_detail_screen.dart';
import 'package:dot/ui/screens/settings_screen.dart';
import 'package:dot/ui/screens/pair_screen.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:dot/ui/screens/workspace_screen.dart';
import 'package:dot/ui/widgets/dot_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late AppState state;
  late Directory directory;
  late Database originalDatabase;
  bool appOwnsState = false;

  setUp(() async {
    appOwnsState = false;
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
    directory = await Directory.systemTemp.createTemp('dot-ui-');
    final db = await DotDatabase.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    originalDatabase = db;
    final repository = ItemRepository(db);
    final devices = DeviceStore(db);
    state = AppState(
      repository: repository,
      devices: devices,
      settings: SettingsStore(await SharedPreferences.getInstance()),
      supportDirectory: directory,
      engine: _LifecycleEngine(
        repository: repository,
        devices: devices,
        localDeviceId: 'local',
        localName: 'MacBook',
        connectionDelay: Duration.zero,
        sendDelay: Duration.zero,
      ),
    );
    state.settings.reducedMotion = true;
  });

  tearDown(() async {
    if (!appOwnsState) {
      await state.engine.stop();
      state.dispose();
    }
    await originalDatabase.close();
    await directory.delete(recursive: true);
  });

  Widget harness(Widget screen, {String? itemId}) => ListenableBuilder(
    listenable: state,
    builder: (context, _) => MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>.value(value: state),
        ChangeNotifierProvider<ItemRepository>.value(value: state.repository),
        ChangeNotifierProvider<DeviceStore>.value(value: state.devices),
        ChangeNotifierProvider<SyncEngine>.value(value: state.engine),
        ChangeNotifierProvider<SettingsStore>.value(value: state.settings),
      ],
      child: MaterialApp(
        theme: lightTheme,
        darkTheme: darkTheme,
        onGenerateRoute: (_) => MaterialPageRoute<void>(
          settings: RouteSettings(arguments: itemId),
          builder: (_) => screen,
        ),
        routes: {'/workspace': (_) => const WorkspaceScreen()},
      ),
    ),
  );

  Future<void> prepare(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(700, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }

  // SQLite FFI completes outside the fake widget-test clock.
  Future<void> settleDatabase(WidgetTester tester) async {
    await tester.pump();
    await tester.runAsync(() async {
      await state.repository.all();
      await Future<void>.delayed(const Duration(milliseconds: 30));
    });
    await tester.pumpAndSettle();
  }

  testWidgets(
    'host pairing shows QR and instructions side by side without clipping',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1180, 760));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(harness(const PairScreen()));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(state.engine.status, ConnectionStatus.pairing);
      expect(find.text('Wacht op je telefoon…'), findsOneWidget);
      final qr = find.byType(QrImageView);
      expect(tester.widget<QrImageView>(qr).size, 240);
      final qrRect = tester.getRect(qr);
      final waitingRect = tester.getRect(find.text('Wacht op je telefoon…'));
      expect(qrRect.right, lessThan(waitingRect.left));
      expect(qrRect.bottom, lessThan(760));
      expect(waitingRect.bottom, lessThan(760));
      expect(find.text('Nieuwe code'), findsOneWidget);
      expect(
        find.widgetWithText(SelectableText, '127.0.0.1:0'),
        findsOneWidget,
      );
      expect(find.widgetWithText(SelectableText, 'DEMO01'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('host pairing remains scrollable in short desktop windows', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 320));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(harness(const PairScreen()));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Wacht op je telefoon…'));
    await tester.pumpAndSettle();
    final rect = tester.getRect(find.text('Wacht op je telefoon…'));
    expect(rect.top, greaterThanOrEqualTo(56));
    expect(rect.bottom, lessThanOrEqualTo(320));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('phone host pairing keeps the centered single column', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(412, 892));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(harness(const PairScreen()));
    await tester.pumpAndSettle();
    expect(tester.getCenter(find.byType(QrImageView)).dx, closeTo(206, 1));
    expect(
      tester.getRect(find.text('Adres')).top,
      greaterThan(tester.getRect(find.byType(QrImageView)).bottom),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'file picker adds every selected local file and handles cancellation',
    (tester) async {
      await prepare(tester);
      final originalPicker = FilePickerPlatform.instance;
      final picker = _TestFilePicker();
      FilePickerPlatform.instance = picker;
      addTearDown(() => FilePickerPlatform.instance = originalPicker);
      await tester.runAsync(() async {
        final first = await File('${directory.path}/first.txt')
            .writeAsString('first');
        final second = await File('${directory.path}/second.txt')
            .writeAsString('second');
        picker.files = [
          _TestPlatformFile(Uri.file(first.path)),
          _TestPlatformFile(Uri.file(second.path)),
        ];
      });
      await tester.pumpWidget(harness(const WorkspaceScreen()));
      await settleDatabase(tester);
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.text('Bestand kiezen'));
        await Future.doWhile(() async {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          return (await state.repository.all()).length != 2;
        }).timeout(const Duration(seconds: 5));
      });
      await settleDatabase(tester);
      expect(find.byType(ItemCard), findsNWidgets(2));
      expect(find.text('first.txt'), findsOneWidget);
      expect(find.text('second.txt'), findsOneWidget);
      picker.files = [];
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      await tester.runAsync(() => tester.tap(find.text('Bestand kiezen')));
      await settleDatabase(tester);
      expect(find.byType(ItemCard), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('manual client pairing previews the peer and can be cancelled', (
    tester,
  ) async {
    await prepare(tester);
    final messenger = tester.binding.defaultBinaryMessenger;
    for (final channel in ['event', 'deviceOrientation']) {
      messenger.setMockMethodCallHandler(
        MethodChannel('dev.steenbakker.mobile_scanner/scanner/$channel'),
        (_) async => null,
      );
    }
    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.steenbakker.mobile_scanner/scanner/method'),
      (call) async {
        if (call.method == 'state') return 0;
        if (call.method == 'request') return false;
        return null;
      },
    );
    final client = FakeSyncEngine(
      repository: state.repository,
      devices: state.devices,
      localDeviceId: 'phone',
      localName: 'Telefoon',
      isHost: false,
    );
    await tester.pumpWidget(
      harness(
        ChangeNotifierProvider<SyncEngine>.value(
          value: client,
          child: const PairScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), '192.168.1.20:48620');
    await tester.enterText(fields.at(1), 'ABC123');
    await tester.ensureVisible(find.text('Verbinden'));
    await tester.tap(find.text('Verbinden'));
    await tester.pumpAndSettle();
    expect(find.text('Bevestig koppeling'), findsOneWidget);
    expect(find.text('Annuleren'), findsOneWidget);
    expect(find.byType(DotCard), findsOneWidget);
    expect(
      find.textContaining('Verbinden met Demo-apparaat op'),
      findsOneWidget,
    );
    await tester.tap(find.text('Annuleren'));
    await tester.pumpAndSettle();
    expect(find.text('Handmatig verbinden'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    client.dispose();
  });

  testWidgets('failed workspace shows recovery and reconnects', (tester) async {
    await prepare(tester);
    final engine = _RecoveryEngine(
      repository: state.repository,
      devices: state.devices,
    );
    await tester.pumpWidget(
      harness(
        ChangeNotifierProvider<SyncEngine>.value(
          value: engine,
          child: const WorkspaceScreen(),
        ),
      ),
    );
    await settleDatabase(tester);
    expect(find.text('Opnieuw verbinden'), findsOneWidget);
    expect(find.text('Test connection error'), findsOneWidget);
    await tester.tap(find.text('Opnieuw verbinden'));
    await settleDatabase(tester);
    expect(engine.reconnectCalls, 1);
    expect(find.text('Opnieuw verbinden'), findsNothing);
    expect(find.text('Test connection error'), findsNothing);
    engine.setStatus(ConnectionStatus.offline);
    await settleDatabase(tester);
    expect(find.text('Opnieuw verbinden'), findsOneWidget);
    engine.setStatus(ConnectionStatus.unpaired);
    await settleDatabase(tester);
    expect(find.text('Apparaat koppelen'), findsOneWidget);
    expect(find.text('Opnieuw verbinden'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    engine.dispose();
  });

  testWidgets('demo pairing clears routes and has no back button', (
    tester,
  ) async {
    await prepare(tester);
    await tester.pumpWidget(harness(const SizedBox()));
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.push(MaterialPageRoute<void>(builder: (_) => const PairScreen()));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await state.engine.confirmPairing(
        await state.engine.previewPairing('demo'),
      );
    });
    await settleDatabase(tester);
    expect(find.byType(WorkspaceScreen), findsOneWidget);
    expect(find.byType(BackButton), findsNothing);
    expect(
      tester.widget<AppBar>(find.byType(AppBar)).automaticallyImplyLeading,
      isFalse,
    );
    expect(
      Navigator.of(tester.element(find.byType(WorkspaceScreen))).canPop(),
      isFalse,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('settings restrict desktop controls to macOS', (tester) async {
    await prepare(tester);
    const loginItemChannel = MethodChannel('dot/login_item');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(loginItemChannel, (call) async {
      switch (call.method) {
        case 'isSupported':
          return true;
        case 'isEnabled':
          return false;
        case 'setEnabled':
          return true;
        default:
          return null;
      }
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(loginItemChannel, null);
    });
    await tester.pumpWidget(harness(const SettingsScreen()));
    await tester.pumpAndSettle();
    expect(
      find.text('Starten bij inloggen'),
      Platform.isMacOS ? findsOneWidget : findsNothing,
    );
    expect(
      find.text('Menubalkicoon'),
      Platform.isMacOS ? findsOneWidget : findsNothing,
    );
    expect(
      find.text('Downloadlocatie'),
      Platform.isMacOS ? findsOneWidget : findsNothing,
    );
    expect(
      tester.widget<Text>(find.text('Instellingen')).style?.fontFamily,
      'Inter',
    );
  });

  testWidgets('workspace renders items and each type chip filters', (
    tester,
  ) async {
    await prepare(tester);
    await tester.runAsync(() async {
      await state.addText('Hallo wereld');
      await state.addLink('https://example.com');
      await state.addNote('Boodschappen', 'Melk');
      final source = await File('${directory.path}/verslag.txt')
          .writeAsString('DOT');
      await state.addFile(source.path);
    });
    await tester.pumpWidget(harness(const WorkspaceScreen()));
    await settleDatabase(tester);
    expect(find.byType(ItemCard), findsNWidgets(4));
    expect(
      find.text(Platform.isMacOS ? 'Van deze Mac' : 'Van deze telefoon'),
      findsNWidgets(4),
    );
    final filters = {
      'Tekst': ItemType.text,
      'Links': ItemType.link,
      'Bestanden': ItemType.file,
      'Notities': ItemType.note,
    };
    for (final entry in filters.entries) {
      final chip = find.widgetWithText(ChoiceChip, entry.key);
      await tester.ensureVisible(chip);
      await tester.tap(chip);
      await settleDatabase(tester);
      expect(find.byType(ItemCard), findsOneWidget);
      expect(
        tester.widget<ItemCard>(find.byType(ItemCard)).item.type,
        entry.value,
      );
    }
    await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'Alles'));
    await tester.tap(find.widgetWithText(ChoiceChip, 'Alles'));
    await settleDatabase(tester);
    expect(find.byType(ItemCard), findsNWidgets(4));
    expect(tester.takeException(), isNull);
  });

  testWidgets('search filters the workspace', (tester) async {
    await prepare(tester);
    await tester.runAsync(() async {
      await state.addText('Hallo wereld');
      await state.addNote('Boodschappen', 'Melk');
    });
    await tester.pumpWidget(harness(const WorkspaceScreen()));
    await settleDatabase(tester);
    await tester.enterText(find.byType(TextField), 'Melk');
    await settleDatabase(tester);
    expect(find.byType(ItemCard), findsOneWidget);
    expect(
      tester.widget<ItemCard>(find.byType(ItemCard)).item.title,
      'Boodschappen',
    );
    await tester.enterText(find.byType(TextField), 'onvindbaar');
    await settleDatabase(tester);
    expect(find.byType(ItemCard), findsNothing);
  });

  testWidgets('reduced motion has no scheduled frames, including pulses', (
    tester,
  ) async {
    await prepare(tester);
    final key = GlobalKey<DotsStageState>();
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 300,
          height: 150,
          child: DotsStage(
            key: key,
            status: ConnectionStatus.searching,
            reducedMotion: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    key.currentState!.sendPulse();
    key.currentState!.receivePulse();
    await tester.pumpAndSettle();
    expect(find.byType(CustomPaint), findsWidgets);
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 300,
          height: 150,
          child: DotsStage(
            key: key,
            status: ConnectionStatus.connected,
            reducedMotion: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets(
    'link details show link actions and react to repository changes',
    (tester) async {
      await prepare(tester);
      final link = (await tester.runAsync(
        () => state.addLink('https://example.com'),
      ))!;
      await tester.pumpWidget(
        harness(const ItemDetailScreen(), itemId: link.id),
      );
      await settleDatabase(tester);
      expect(find.text('Open link'), findsOneWidget);
      expect(find.text('Openen'), findsNothing);
      expect(find.text('Toon in map'), findsNothing);
      expect(find.text('Delen'), findsOneWidget);
      await tester.runAsync(() => state.togglePin(link.id));
      await settleDatabase(tester);
      expect(find.text('Losmaken'), findsOneWidget);
    },
  );

  testWidgets('file details show only file actions', (tester) async {
    await prepare(tester);
    final file = (await tester.runAsync(() async {
      final source = await File('${directory.path}/bestand.txt')
          .writeAsString('DOT');
      return state.addFile(source.path);
    }))!;
    await tester.pumpWidget(harness(const ItemDetailScreen(), itemId: file.id));
    await settleDatabase(tester);
    expect(find.text('Openen'), findsOneWidget);
    expect(find.text('Open link'), findsNothing);
    expect(find.text('Delen'), findsOneWidget);
    expect(
      find.text('Toon in map'),
      Platform.isMacOS ? findsOneWidget : findsNothing,
    );
  });

  testWidgets('inactive keeps networking active; background states stop it', (
    tester,
  ) async {
    final engine = state.engine as _LifecycleEngine;
    appOwnsState = true;
    await tester.pumpWidget(DotApp(state: state));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(milliseconds: 1));
    engine.activeStates.clear();
    engine.stopCalls = 0;

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump(const Duration(milliseconds: 1));
    expect(engine.activeStates, [true]);
    expect(engine.stopCalls, 0);

    for (final lifecycle in [
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.detached,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(lifecycle);
      expect(engine.activeStates.last, isFalse);
    }
    expect(engine.stopCalls, 3);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(milliseconds: 1));
    expect(engine.activeStates.last, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Eerst bekijken enters demo mode and opens workspace', (
    tester,
  ) async {
    await prepare(tester);
    appOwnsState = true;
    await tester.pumpWidget(DotApp(state: state));
    state.settings.reducedMotion = true;
    // Start the callback in the real async zone so SQLite and the demo
    // engine's connection timer can finish before pumping the new route.
    await tester.runAsync(() async {
      await tester.tap(find.text('Eerst bekijken'));
      await Future.doWhile(() async {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        return !state.isDemoMode ||
            state.engine.status != ConnectionStatus.connected;
      }).timeout(const Duration(seconds: 5));
      await state.engine.syncNow();
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await settleDatabase(tester);
    expect(state.isDemoMode, isTrue);
    expect(find.byType(WorkspaceScreen), findsOneWidget);
    expect(find.byType(BackButton), findsNothing);
    expect(
      Navigator.of(tester.element(find.byType(WorkspaceScreen))).canPop(),
      isFalse,
    );
    await tester.tap(find.byTooltip('Instellingen'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _TestFilePicker extends FilePickerPlatform {
  List<PlatformFile> files = [];
  @override
  Future<List<PlatformFile>> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async => files;
}

final class _TestPlatformFile extends PlatformFile {
  _TestPlatformFile(this.uri);
  @override
  final Uri uri;
  @override
  String get name => uri.pathSegments.last;
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Only file paths are used by this test');
}

class _RecoveryEngine extends FakeSyncEngine {
  _RecoveryEngine({required super.repository, required super.devices})
    : super(localDeviceId: 'local', localName: 'Test');
  ConnectionStatus currentStatus = ConnectionStatus.failed;
  int reconnectCalls = 0;
  @override
  ConnectionStatus get status => currentStatus;
  @override
  String? get lastError =>
      currentStatus == ConnectionStatus.failed ? 'Test connection error' : null;
  void setStatus(ConnectionStatus value) {
    currentStatus = value;
    notifyListeners();
  }

  @override
  Future<void> reconnect() async {
    reconnectCalls++;
    setStatus(ConnectionStatus.connected);
  }
}

class _LifecycleEngine extends FakeSyncEngine {
  _LifecycleEngine({
    required super.repository,
    required super.devices,
    required super.localDeviceId,
    required super.localName,
    super.connectionDelay,
    super.sendDelay,
  });

  final activeStates = <bool>[];
  int stopCalls = 0;

  @override
  Future<void> onAppLifecycle({required bool active}) async {
    activeStates.add(active);
    await super.onAppLifecycle(active: active);
  }

  @override
  Future<void> stop() async {
    stopCalls++;
    await super.stop();
  }
}
