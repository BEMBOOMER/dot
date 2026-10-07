import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';

import '../../core/app_state.dart';
import '../../core/settings_store.dart';
import '../widgets/dot_widgets.dart';
import '../../platform/update_checker.dart';

import 'package:url_launcher/url_launcher.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Instellingen',
          style: TextStyle(fontFamily: 'Inter'),
        ),
      ),
      body: ScreenContent(
        child: Consumer2<SettingsStore, AppState>(
          builder: (context, settings, appState, child) {
            return ListView(
              padding: EdgeInsets.all(
                MediaQuery.sizeOf(context).width > 800 ? 32 : 20,
              ),
              children: _groups(context, [
                _buildSectionHeader(context, 'Algemeen'),
                ListTile(
                  title: const Text('Thema'),
                  trailing: DropdownButton<ThemeMode>(
                    value: settings.themeMode,
                    onChanged: (ThemeMode? newValue) {
                      if (newValue != null) {
                        settings.themeMode = newValue;
                      }
                    },
                    items: const [
                      DropdownMenuItem(
                        value: ThemeMode.system,
                        child: Text('Systeem'),
                      ),
                      DropdownMenuItem(
                        value: ThemeMode.light,
                        child: Text('Licht'),
                      ),
                      DropdownMenuItem(
                        value: ThemeMode.dark,
                        child: Text('Donker'),
                      ),
                    ],
                  ),
                ),
                SwitchListTile(
                  title: const Text('Verminderde animaties'),
                  value: settings.reducedMotion,
                  onChanged: (val) => settings.reducedMotion = val,
                ),
                SwitchListTile(
                  title: const Text('Meldingen'),
                  value: settings.notifications,
                  onChanged: (val) => settings.notifications = val,
                ),
                SwitchListTile(
                  title: const Text('Automatisch opnieuw verbinden'),
                  value: settings.autoReconnect,
                  onChanged: (val) => settings.autoReconnect = val,
                ),

                if (Platform.isMacOS) ...[
                  const Divider(),
                  _buildSectionHeader(context, 'macOS'),
                  SwitchListTile(
                    title: const Text('Starten bij inloggen'),
                    value: settings.launchAtLogin,
                    onChanged: (val) => settings.launchAtLogin = val,
                  ),
                  SwitchListTile(
                    title: const Text('Menubalkicoon'),
                    value: settings.menuBarIcon,
                    onChanged: (val) => settings.menuBarIcon = val,
                  ),
                  ListTile(
                    title: const Text('Downloadlocatie'),
                    subtitle: Text(settings.downloadDir ?? 'Standaardmap'),
                    trailing: DotButton(
                      variant: DotButtonStyle.ghost,
                      label: 'Wijzigen',
                      onPressed: () async {
                        final dir = await FilePicker.getDirectoryPath();
                        if (dir != null) {
                          settings.downloadDir = dir;
                        }
                      },
                    ),
                  ),
                ],

                const Divider(),
                _buildSectionHeader(context, 'Apparaat'),
                ListTile(
                  title: const Text('Apparaatnaam'),
                  subtitle: Text(
                    settings.deviceName ?? appState.engine.localName,
                  ),
                  trailing: DotButton(
                    variant: DotButtonStyle.ghost,
                    label: 'Wijzigen',
                    onPressed: () => _renameDevice(context, settings),
                  ),
                ),

                const Divider(),
                _buildSectionHeader(context, 'Gegevens'),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16.0,
                    vertical: 8.0,
                  ),
                  child: DotButton(
                    variant: DotButtonStyle.ghost,
                    label: 'Geschiedenis wissen',
                    color: Theme.of(context).colorScheme.error,
                    onPressed: () => _confirmClearHistory(context, appState),
                  ),
                ),

                const Divider(),
                _buildSectionHeader(context, 'Over'),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16.0,
                    vertical: 8.0,
                  ),
                  child: DotButton(
                    variant: DotButtonStyle.ghost,
                    label: 'Updates controleren',
                    color: Theme.of(context).colorScheme.primary,
                    onPressed: () => _checkUpdates(context),
                  ),
                ),

                if (appState.isDemoMode) ...[
                  const Divider(),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16.0,
                      vertical: 8.0,
                    ),
                    child: DotButton(
                      variant: DotButtonStyle.ghost,
                      label: 'Demo afsluiten',
                      color: Theme.of(context).colorScheme.primary,
                      onPressed: () => appState.exitDemoMode(),
                    ),
                  ),
                ],
              ]),
            );
          },
        ),
      ),
    );
  }

  Future<void> _checkUpdates(BuildContext context) async {
    try {
      final update = await checkForDotUpdate();
      if (!context.mounted) return;
      if (update == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Je gebruikt de nieuwste versie.')),
        );
        return;
      }
      final open = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Versie ${update.version} is beschikbaar'),
          content: SingleChildScrollView(child: Text(update.notes)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Later'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Download bekijken'),
            ),
          ],
        ),
      );
      if (open == true) {
        if (!await launchUrl(
          update.url,
          mode: LaunchMode.externalApplication,
        )) {
          throw StateError('Release openen mislukt');
        }
      }
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Updates controleren lukt nog niet. Probeer opnieuw.'),
        ),
      );
    }
  }

  Widget _buildSectionHeader(BuildContext context, String title) =>
      _SettingsHeading(title);

  List<Widget> _groups(BuildContext context, List<Widget> rows) {
    final result = <Widget>[];
    final group = <Widget>[];
    void flush() {
      if (group.isEmpty) return;
      result.add(
        DotCard(
          child: Column(
            children: [
              for (var i = 0; i < group.length; i++) ...[
                if (i > 0) const Divider(indent: 16, endIndent: 16),
                group[i],
              ],
            ],
          ),
        ),
      );
      result.add(const SizedBox(height: 24));
      group.clear();
    }

    for (final row in rows) {
      if (row is Divider) continue;
      if (row is _SettingsHeading) {
        flush();
        result.add(row);
      } else {
        group.add(row);
      }
    }
    flush();
    return result;
  }

  Future<void> _renameDevice(
    BuildContext context,
    SettingsStore settings,
  ) async {
    final controller = TextEditingController(text: settings.deviceName);
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Apparaatnaam wijzigen'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'Nieuwe naam'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuleren'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Opslaan'),
          ),
        ],
      ),
    );

    if (newName != null && newName.trim().isNotEmpty) {
      settings.deviceName = newName.trim();
    }
  }

  Future<void> _confirmClearHistory(
    BuildContext context,
    AppState appState,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Geschiedenis wissen'),
        content: const Text(
          'Weet je zeker dat je je geschiedenis wilt wissen? Dit kan niet ongedaan worden gemaakt.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuleren'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Wissen',
              style: TextStyle(color: Color(0xFFE5484D)),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      appState.clearHistory();
    }
  }
}

class _SettingsHeading extends StatelessWidget {
  final String title;
  const _SettingsHeading(this.title);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
    child: Text(title, style: Theme.of(context).textTheme.bodySmall),
  );
}
