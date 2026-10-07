import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../platform/file_actions.dart';

import 'package:share_plus/share_plus.dart';

import '../../core/app_state.dart';
import '../../core/item_repository.dart';
import '../../core/sync_engine.dart';
import '../../core/models.dart';
import '../widgets/dot_widgets.dart';
import '../theme/dot_theme.dart';

class ItemDetailScreen extends StatefulWidget {
  const ItemDetailScreen({super.key});

  @override
  State<ItemDetailScreen> createState() => _ItemDetailScreenState();
}

class _ItemDetailScreenState extends State<ItemDetailScreen> {
  Timer? _debounce;
  final TextEditingController _noteController = TextEditingController();
  String? _loadedItemId;
  ItemRepository? _repository;
  Future<DotItem?>? _itemFuture;

  void _reloadItem() {
    if (!mounted || _loadedItemId == null) return;
    final future = _repository!.get(_loadedItemId!);
    if (!mounted) return;
    setState(() {
      _itemFuture = future;
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final repository = context.watch<ItemRepository>();
    final id = ModalRoute.of(context)!.settings.arguments as String;
    if (repository != _repository || id != _loadedItemId) {
      _repository?.removeListener(_reloadItem);
      _repository = repository;
      _repository!.addListener(_reloadItem);
      _loadedItemId = id;
      _itemFuture = repository.get(id);
      _debounce?.cancel();
      _initializedNoteId = null;
      _dismissedConflict = false;
      _noteController.clear();
    }
  }

  String? _initializedNoteId;
  bool _dismissedConflict = false;

  @override
  void dispose() {
    _repository?.removeListener(_reloadItem);
    _debounce?.cancel();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer3<AppState, ItemRepository, SyncEngine>(
      builder: (context, appState, repo, engine, child) {
        return FutureBuilder<DotItem?>(
          future: _itemFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting &&
                !snapshot.hasData) {
              return const Scaffold(
                body: ScreenContent(
                  child: Center(child: CircularProgressIndicator()),
                ),
              );
            }
            if (snapshot.hasError) {
              return const Scaffold(
                body: ScreenContent(
                  child: Center(child: Text('Item laden lukt nog niet')),
                ),
              );
            }
            final item = snapshot.data;
            if (item == null || item.deleted) {
              return Scaffold(
                appBar: AppBar(
                  title: const Text(
                    'Details',
                    style: TextStyle(fontFamily: 'Inter'),
                  ),
                ),
                body: ScreenContent(
                  child: const Center(child: Text('Item niet gevonden')),
                ),
              );
            }

            if (item.type == ItemType.note && _initializedNoteId != item.id) {
              _noteController.text = item.body;
              _initializedNoteId = item.id;
            }

            return Scaffold(
              appBar: AppBar(
                title: Text(
                  itemTypeLabel(item.type),
                  style: const TextStyle(fontFamily: 'Inter'),
                ),
                actions: [
                  IconButton(
                    icon: Icon(
                      item.pinned ? Icons.push_pin : Icons.push_pin_outlined,
                    ),
                    onPressed: () => appState.togglePin(item.id),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _confirmDelete(context, appState, item.id),
                  ),
                ],
              ),
              body: ScreenContent(
                child: ListView(
                  padding: EdgeInsets.all(
                    MediaQuery.sizeOf(context).width > 800 ? 32 : 20,
                  ),
                  children: [
                    if (item.type == ItemType.note &&
                        item.conflictOf != null &&
                        !_dismissedConflict) ...[
                      DotCard(
                        color: DotColors.muted(context),
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Andere versie van deze notitie',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 16),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  DotButton(
                                    variant: DotButtonStyle.secondary,
                                    label: 'Samenvoegen',
                                    color: Theme.of(context)
                                        .colorScheme
                                        .primary, // lime
                                    onPressed: () async {
                                      final original = await repo.get(
                                        item.conflictOf!,
                                      );
                                      if (original != null) {
                                        final mergedBody =
                                            '${original.body}\n\nAndere versie:\n\n${item.body}';
                                        await appState.updateNote(
                                          original.id,
                                          mergedBody,
                                          title: original.title,
                                        );
                                      }
                                      if (original == null) return;
                                      await appState.deleteItem(item.id);
                                      if (context.mounted) {
                                        Navigator.pop(context);
                                      }
                                    },
                                  ),
                                  DotButton(
                                    variant: DotButtonStyle.secondary,
                                    label: 'Deze houden',
                                    color: Colors.white,
                                    onPressed: () {
                                      setState(() {
                                        _dismissedConflict = true;
                                      });
                                    },
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    Row(
                      children: [
                        Text(
                          itemOriginLabel(context, item),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        StatusPill(
                          label: syncStateLabel(item.syncState),
                          color: _getSyncStateColor(item.syncState),
                        ),
                      ],
                    ),
                    if (item.syncState == SyncState.sending &&
                        item.type == ItemType.file &&
                        item.progress > 0) ...[
                      const SizedBox(height: 16),
                      LinearProgressIndicator(value: item.progress),
                    ],
                    const SizedBox(height: 24),
                    _buildContent(context, item, appState),
                    const SizedBox(height: 24),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _buildActions(context, item, appState, engine),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildContent(BuildContext context, DotItem item, AppState appState) {
    switch (item.type) {
      case ItemType.text:
      case ItemType.link:
        return DotCard(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: SelectableText(item.body),
          ),
        );
      case ItemType.note:
        return DotCard(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _noteController,
              maxLines: null,
              decoration: const InputDecoration(
                border: InputBorder.none,
                hintText: 'Notitie...',
              ),
              onChanged: (val) {
                if (_debounce?.isActive ?? false) _debounce!.cancel();
                _debounce = Timer(const Duration(milliseconds: 600), () {
                  appState.updateNote(item.id, val, title: item.title);
                });
              },
            ),
          ),
        );
      case ItemType.file:
        return DotCard(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.fileName ?? item.title,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                if (item.fileSize != null) ...[
                  const SizedBox(height: 4),
                  Text('${(item.fileSize! / 1024).toStringAsFixed(1)} KB'),
                ],
              ],
            ),
          ),
        );
    }
  }

  List<Widget> _buildActions(
    BuildContext context,
    DotItem item,
    AppState appState,
    SyncEngine engine,
  ) {
    final actions = <Widget>[];

    if (item.type != ItemType.file || item.localPath != null) {
      actions.add(
        DotButton(
          variant: DotButtonStyle.primary,
          label: 'Kopiëren',
          onPressed: () => appState.copyItem(item.id),
          color: Theme.of(context).colorScheme.primary,
        ),
      );
    }

    if (item.type == ItemType.link && item.body.isNotEmpty) {
      actions.add(
        DotButton(
          variant: DotButtonStyle.secondary,
          label: 'Open link',
          color: Theme.of(context).colorScheme.primary,
          onPressed: () async {
            final uri = Uri.tryParse(item.body);
            if (uri != null && await canLaunchUrl(uri)) {
              await launchUrl(uri);
            }
          },
        ),
      );
    }

    if (item.type == ItemType.file && item.localPath != null) {
      actions.add(
        DotButton(
          variant: DotButtonStyle.secondary,
          label: 'Openen',
          color: Theme.of(context).colorScheme.primary,
          onPressed: () {
            _runAction(() => openDotFile(item.localPath!));
          },
        ),
      );

      if (Platform.isMacOS) {
        actions.add(
          DotButton(
            variant: DotButtonStyle.secondary,
            label: 'Toon in map',
            onPressed: () async {
              await _runAction(() => revealDotFile(item.localPath!));
            },
          ),
        );
      }
    }

    if (item.type != ItemType.file || item.localPath != null) {
      actions.add(
        DotButton(
          variant: DotButtonStyle.secondary,
          label: 'Delen',
          onPressed: () {
            if (item.type == ItemType.file && item.localPath != null) {
              _runAction(() => shareDotFile(item.localPath!));
            } else {
              _runAction(() async {
                await SharePlus.instance.share(ShareParams(text: item.body));
              });
            }
          },
        ),
      );
    }

    if (item.syncState == SyncState.failed ||
        item.syncState == SyncState.waiting) {
      actions.add(
        DotButton(
          variant: DotButtonStyle.secondary,
          label: 'Opnieuw versturen',
          color: const Color(0xFFF5A524),
          onPressed: () => engine.retry(item.id),
        ),
      );
    }

    actions.add(
      DotButton(
        variant: DotButtonStyle.secondary,
        label: item.pinned ? 'Losmaken' : 'Vastzetten',
        onPressed: () => appState.togglePin(item.id),
      ),
    );

    actions.add(
      DotButton(
        variant: DotButtonStyle.ghost,
        label: 'Verwijderen',
        color: Theme.of(context).colorScheme.error,
        onPressed: () => _confirmDelete(context, appState, item.id),
      ),
    );

    return actions;
  }

  Future<void> _runAction(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Deze actie lukt nog niet. Probeer opnieuw.'),
        ),
      );
    }
  }

  Color _getSyncStateColor(SyncState state) => switch (state) {
    SyncState.local => DotColors.secondary(context),
    SyncState.received => DotColors.success(context),
    SyncState.failed => Theme.of(context).colorScheme.error,
    SyncState.waiting => DotColors.warning(context),
    SyncState.sending => Theme.of(context).colorScheme.primary,
  };

  Future<void> _confirmDelete(
    BuildContext context,
    AppState appState,
    String id,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Verwijderen'),
        content: const Text('Weet je zeker dat je dit item wilt verwijderen?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuleren'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Verwijderen',
              style: TextStyle(color: Color(0xFFE5484D)),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      appState.deleteItem(id);
      if (context.mounted) Navigator.pop(context);
    }
  }
}
