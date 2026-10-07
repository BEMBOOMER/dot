import 'dart:io';

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
import 'package:dot/ui/screens/item_detail_screen.dart';
import 'package:dot/ui/screens/settings_screen.dart';
import 'package:dot/ui/screens/workspace_screen.dart';
import 'package:dot/ui/widgets/brutal_widgets.dart';
import 'package:flutter/material.dart';
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
      engine: FakeSyncEngine(
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
    await tester.tap(find.byTooltip('Instellingen'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
