import 'dart:async';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';

import '../../core/app_state.dart';
import '../../core/item_repository.dart';
import '../../core/sync_engine.dart';
import '../../core/settings_store.dart';
import '../../core/models.dart';
import '../widgets/dot_widgets.dart';
import '../dots/dots_stage.dart';
import '../theme/dot_theme.dart';

class WorkspaceScreen extends StatefulWidget {
  final void Function(List<String> paths)? onFilesDropped;

  const WorkspaceScreen({super.key, this.onFilesDropped});

  @override
  State<WorkspaceScreen> createState() => _WorkspaceScreenState();
}

class _WorkspaceScreenState extends State<WorkspaceScreen> {
  String _query = '';
  ItemType? _selectedFilter;
  String? _selectedItemId;
  final FocusNode _searchFocusNode = FocusNode();
  final GlobalKey<DotsStageState> _dotsStageKey = GlobalKey<DotsStageState>();
  StreamSubscription<SyncEvent>? _eventSub;

  final Map<String, ItemType?> _filterMap = {
    'Alles': null,
    'Tekst': ItemType.text,
    'Links': ItemType.link,
    'Bestanden': ItemType.file,
    'Notities': ItemType.note,
  };

  @override
  void initState() {
    super.initState();
    final engine = context.read<SyncEngine>();
    _eventSub = engine.events.listen((event) {
      if (!mounted) return;
      if (event is ItemSentEvent) {
        _dotsStageKey.currentState?.sendPulse();
      } else if (event is ItemReceivedEvent) {
        _dotsStageKey.currentState?.receivePulse();
      }
    });
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _showAddModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _AddModalSheet(),
    );
  }

  void _handlePasteAndSend() async {
    final item = await context.read<AppState>().pasteAndSend();
    if (!mounted) return;
    if (item != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Klembord geplakt en verstuurd')),
      );
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Klembord is leeg')));
    }
  }

  Widget _buildListPane(List<DotItem> items) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
          child: TextField(
            focusNode: _searchFocusNode,
            onChanged: (val) => setState(() => _query = val),
            decoration: InputDecoration(
              hintText: 'Zoeken…',
              prefixIcon: const Icon(Icons.search),

              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
            ),
          ),
        ),
        ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (bounds) => const LinearGradient(
            colors: [Colors.white, Colors.white, Colors.transparent],
            stops: [0, 0.92, 1],
          ).createShader(bounds),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(20, 0, 32, 0),
            child: Row(
              children: _filterMap.entries.map((entry) {
                final isSelected = _selectedFilter == entry.value;
                return Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: ChoiceChip(
                    label: Text(entry.key),
                    selected: isSelected,
                    onSelected: (selected) {
                      if (selected) {
                        setState(() => _selectedFilter = entry.value);
                      }
                    },
                    showCheckmark: false,
                    selectedColor: Theme.of(context).colorScheme.primary,
                    labelStyle: TextStyle(
                      color: isSelected
                          ? Colors.white
                          : Theme.of(context).colorScheme.onSurface,
                      fontFamily: 'Inter',
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: items.isEmpty
              ? const EmptyState(
                  icon: Icons.inbox_outlined,
                  message: 'Geen items gevonden in je werkruimte.',
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20.0,
                    vertical: 8.0,
                  ),
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    final isMac = MediaQuery.of(context).size.width > 800;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12.0),
                      child: ItemCard(
                        item: item,
                        onTap: () {
                          if (isMac) {
                            setState(() => _selectedItemId = item.id);
                          } else {
                            Navigator.pushNamed(
                              context,
                              '/item',
                              arguments: item.id,
                            );
                          }
                        },
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildDetailPane(DotItem? item) {
    if (item == null) {
      return const Center(
        child: EmptyState(
          icon: Icons.touch_app_outlined,
          message: 'Selecteer een item om details te bekijken',
        ),
      );
    }

    final appState = context.read<AppState>();
    final engine = context.read<SyncEngine>();

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                itemTypeLabel(item.type),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const Spacer(),
              IconButton(
                icon: Icon(
                  item.pinned ? Icons.push_pin : Icons.push_pin_outlined,
                ),
                onPressed: () => appState.togglePin(item.id),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () => appState.deleteItem(item.id),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            itemOriginLabel(context, item),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: DotCard(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: SelectableText(
                  item.type == ItemType.file
                      ? 'Bestand: ${item.fileName ?? item.title}\nGrootte: ${item.fileSize != null ? "${(item.fileSize! / 1024).toStringAsFixed(1)} KB" : "Onbekend"}'
                      : item.body,
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              DotButton(
                variant: DotButtonStyle.primary,
                label: 'Kopiëren',
                color: Theme.of(context).colorScheme.primary,
                onPressed: () => appState.copyItem(item.id),
              ),
              if (item.syncState == SyncState.failed ||
                  item.syncState == SyncState.waiting)
                DotButton(
                  variant: DotButtonStyle.secondary,
                  label: 'Opnieuw versturen',
                  color: DotColors.warning(context),
                  onPressed: () => engine.retry(item.id),
                ),
              DotButton(
                variant: DotButtonStyle.secondary,
                label: 'Volledige details',
                color: Theme.of(context).colorScheme.primary,
                onPressed: () =>
                    Navigator.pushNamed(context, '/item', arguments: item.id),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMac = MediaQuery.of(context).size.width > 800;
    final engine = context.watch<SyncEngine>();
    final settings = context.watch<SettingsStore>();

    final workspace = CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyN, meta: true):
            _showAddModal,
        const SingleActivator(LogicalKeyboardKey.enter, meta: true): () =>
            context.read<SyncEngine>().syncNow(),
        const SingleActivator(LogicalKeyboardKey.keyF, meta: true): () =>
            _searchFocusNode.requestFocus(),
        const SingleActivator(LogicalKeyboardKey.keyV, meta: true):
            _handlePasteAndSend,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: Theme.of(context).brightness == Brightness.dark
              ? DotColors.bgDark
              : DotColors.bg,
          appBar: AppBar(
            automaticallyImplyLeading: false,
            title: const Text('DOT', style: TextStyle(fontFamily: 'Inter')),
            backgroundColor: Colors.transparent,
            elevation: 0,
            actions: [
              if (isMac)
                DotButton(
                  variant: DotButtonStyle.primary,
                  label: 'Toevoegen',
                  icon: Icons.add,
                  onPressed: _showAddModal,
                ),
              IconButton(
                icon: const Icon(Icons.devices_outlined),
                tooltip: 'Apparaten',
                onPressed: () => Navigator.pushNamed(context, '/devices'),
              ),
              IconButton(
                icon: const Icon(Icons.settings_outlined),
                tooltip: 'Instellingen',
                onPressed: () => Navigator.pushNamed(context, '/settings'),
              ),
            ],
          ),
          body: SafeArea(
            child: Column(
              children: [
                // DotsStage on top
                SizedBox(
                  height: isMac ? 190 : 150,
                  child: Center(
                    child: DotsStage(
                      key: _dotsStageKey,
                      status: engine.status,
                      reducedMotion: settings.reducedMotion,
                    ),
                  ),
                ),
                // StatusLine below dots
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20.0,
                    vertical: 4.0,
                  ),
                  child: StatusLine(
                    status: engine.status,
                    peerName: engine.peerName,
                  ),
                ),
                if (engine.status == ConnectionStatus.failed ||
                    engine.status == ConnectionStatus.offline ||
                    engine.status == ConnectionStatus.unpaired)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                    child: Column(
                      children: [
                        DotButton(
                          variant: DotButtonStyle.secondary,
                          label: engine.status == ConnectionStatus.unpaired
                              ? 'Apparaat koppelen'
                              : 'Opnieuw verbinden',
                          onPressed: () {
                            if (engine.status == ConnectionStatus.unpaired) {
                              Navigator.pushNamed(context, '/pair');
                            } else {
                              engine.reconnect();
                            }
                          },
                        ),
                        if (engine.lastError != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            engine.lastError!,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ],
                    ),
                  ),
                const SizedBox(height: 8),
                Expanded(
                  child: Consumer<ItemRepository>(
                    builder: (context, repo, child) {
                      return FutureBuilder<List<DotItem>>(
                        future: repo.all(query: _query, type: _selectedFilter),
                        builder: (context, snapshot) {
                          final items = snapshot.data ?? [];
                          if (isMac) {
                            DotItem? selectedItem;
                            if (_selectedItemId != null) {
                              selectedItem = items
                                  .where((i) => i.id == _selectedItemId)
                                  .firstOrNull;
                            }
                            return Row(
                              children: [
                                Expanded(flex: 1, child: _buildListPane(items)),
                                const VerticalDivider(width: 1),
                                Expanded(
                                  flex: 2,
                                  child: _buildDetailPane(selectedItem),
                                ),
                              ],
                            );
                          }
                          return _buildListPane(items);
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          floatingActionButton: isMac
              ? null
              : Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Theme.of(context).colorScheme.primary
                            .withValues(alpha: .22),
                        blurRadius: 20,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  width: 60,
                  height: 60,
                  child: FloatingActionButton(
                    elevation: 0,
                    highlightElevation: 0,
                    focusElevation: 0,
                    hoverElevation: 0,
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Colors.white,
                    onPressed: _showAddModal,
                    shape: const CircleBorder(),
                    child: const Icon(Icons.add, size: 28),
                  ),
                ),
        ),
      ),
    );
    if (!Platform.isMacOS) return workspace;
    return DropTarget(
      enable: ModalRoute.of(context)?.isCurrent ?? true,
      onDragDone: (details) async {
        final paths = details.files.map((file) => file.path).toList();
        if (widget.onFilesDropped != null) {
          widget.onFilesDropped!(paths);
          return;
        }
        final state = context.read<AppState>();
        try {
          for (final path in paths) {
            await state.addFile(path);
          }
        } catch (_) {
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Bestand toevoegen lukt nog niet. Probeer opnieuw.',
              ),
            ),
          );
        }
      },
      child: workspace,
    );
  }
}

class _AddModalSheet extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final appState = context.read<AppState>();
    final theme = Theme.of(context);
    final surface = theme.colorScheme.surface;

    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        top: 24,
        left: 24,
        right: 24,
      ),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Material(
        color: Colors.transparent,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (MediaQuery.sizeOf(context).width <= 800) ...[
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: theme.dividerColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
            const Text(
              'Toevoegen',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 22,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.text_fields),
              title: const Text('Tekst'),
              onTap: () {
                Navigator.pop(context);
                _promptText(context, appState);
              },
            ),
            ListTile(
              leading: const Icon(Icons.link),
              title: const Text('Link'),
              onTap: () {
                Navigator.pop(context);
                _promptLink(context, appState);
              },
            ),
            ListTile(
              leading: const Icon(Icons.content_paste),
              title: const Text('Plakken en versturen'),
              onTap: () async {
                Navigator.pop(context);
                final item = await appState.pasteAndSend();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        item != null
                            ? 'Klembord verstuurd'
                            : 'Klembord is leeg',
                      ),
                    ),
                  );
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.insert_drive_file),
              title: const Text('Bestand kiezen'),
              onTap: () async {
                Navigator.pop(context);
                final files = await FilePicker.pickFiles();
                for (final file in files) {
                  final path = file.path;
                  if (path != null) {
                    await appState.addFile(path);
                  }
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.note_add),
              title: const Text('Nieuwe notitie'),
              onTap: () {
                Navigator.pop(context);
                _promptNote(context, appState);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _promptText(BuildContext context, AppState appState) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tekst toevoegen'),
        content: TextField(
          controller: controller,
          maxLines: 4,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Typ je bericht…'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuleren'),
          ),
          ElevatedButton(
            onPressed: () {
              final val = controller.text.trim();
              if (val.isNotEmpty) {
                appState.addText(val);
              }
              Navigator.pop(ctx);
            },
            child: const Text('Versturen'),
          ),
        ],
      ),
    );
  }

  void _promptLink(BuildContext context, AppState appState) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Link toevoegen'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'https://example.com'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuleren'),
          ),
          ElevatedButton(
            onPressed: () {
              final val = controller.text.trim();
              if (val.isNotEmpty) {
                try {
                  appState.addLink(val);
                } catch (e) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text(e.toString())));
                }
              }
              Navigator.pop(ctx);
            },
            child: const Text('Versturen'),
          ),
        ],
      ),
    );
  }

  void _promptNote(BuildContext context, AppState appState) {
    final titleCtrl = TextEditingController();
    final bodyCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nieuwe notitie'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleCtrl,
              autofocus: true,
              decoration: const InputDecoration(hintText: 'Titel'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: bodyCtrl,
              maxLines: 4,
              decoration: const InputDecoration(hintText: 'Inhoud…'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuleren'),
          ),
          ElevatedButton(
            onPressed: () {
              final title = titleCtrl.text.trim();
              if (title.isNotEmpty) {
                appState.addNote(title, bodyCtrl.text);
              }
              Navigator.pop(ctx);
            },
            child: const Text('Opslaan'),
          ),
        ],
      ),
    );
  }
}
