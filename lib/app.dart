import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/app_state.dart';
import 'core/device_store.dart';
import 'core/item_repository.dart';
import 'core/settings_store.dart';
import 'core/sync_engine.dart';
import 'ui/screens/welcome_screen.dart';
import 'ui/screens/pair_screen.dart';
import 'ui/screens/workspace_screen.dart';
import 'ui/screens/item_detail_screen.dart';
import 'ui/screens/devices_screen.dart';
import 'ui/screens/settings_screen.dart';

class DotApp extends StatefulWidget {
  final AppState state;
  const DotApp({super.key, required this.state});
  @override
  State<DotApp> createState() => _DotAppState();
}

class _DotAppState extends State<DotApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    unawaited(
      widget.state.engine.onAppLifecycle(
        active: state == AppLifecycleState.resumed,
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.state.dispose();
    super.dispose();
  }

  ThemeData _theme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    return ThemeData(
      brightness: brightness,
      fontFamily: 'SpaceGrotesk',
      scaffoldBackgroundColor: dark
          ? const Color(0xFF121212)
          : const Color(0xFFF5F0E8),
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFFFF4F81),
        brightness: brightness,
      ),
      textTheme: TextTheme(
        headlineLarge: TextStyle(
          fontFamily: 'ArchivoBlack',
          color: dark ? const Color(0xFFF5F0E8) : const Color(0xFF1A1A1A),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.state,
    builder: (context, child) => MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>.value(value: widget.state),
        ChangeNotifierProvider<ItemRepository>.value(
          value: widget.state.repository,
        ),
        ChangeNotifierProvider<DeviceStore>.value(value: widget.state.devices),
        ChangeNotifierProvider<SettingsStore>.value(
          value: widget.state.settings,
        ),
        ChangeNotifierProvider<SyncEngine>.value(value: widget.state.engine),
      ],
      child: Consumer<SettingsStore>(
        builder: (context, settings, _) => MaterialApp(
          title: 'DOT',
          debugShowCheckedModeBanner: false,
          theme: _theme(Brightness.light),
          darkTheme: _theme(Brightness.dark),
          themeMode: settings.themeMode,
          initialRoute: settings.onboarded ? '/workspace' : '/welcome',
          routes: {
            '/welcome': (_) => const WelcomeScreen(),
            '/pair': (_) => const PairScreen(),
            '/workspace': (_) => const WorkspaceScreen(),
            '/item': (_) => const ItemDetailScreen(),
            '/devices': (_) => const DevicesScreen(),
            '/settings': (_) => const SettingsScreen(),
          },
        ),
      ),
    ),
  );
}
