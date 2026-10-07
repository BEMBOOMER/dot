import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/device_store.dart';
import '../../core/sync_engine.dart';
import '../../core/models.dart';
import '../widgets/dot_widgets.dart';

class DevicesScreen extends StatelessWidget {
  const DevicesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Apparaten', style: TextStyle(fontFamily: 'Inter')),
      ),
      body: ScreenContent(
        child: Consumer2<DeviceStore, SyncEngine>(
          builder: (context, devicesStore, engine, child) {
            final devices = devicesStore.devices;

            if (devices.isEmpty) {
              return const EmptyState(
                icon: Icons.devices_outlined,
                message: 'Geen apparaten gekoppeld',
              );
            }

            return ListView.builder(
              padding: EdgeInsets.all(
                MediaQuery.sizeOf(context).width > 800 ? 32 : 20,
              ),
              itemCount: devices.length,
              itemBuilder: (context, index) {
                final device = devices[index];
                final isReachable =
                    engine.status == ConnectionStatus.connected &&
                    engine.peerName == device.name;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 16.0),
                  child: DotCard(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                device.platform == DevicePlatform.macos
                                    ? Icons.laptop_mac
                                    : Icons.phone_android,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  device.name,
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                              ),
                              StatusPill(
                                label: isReachable ? 'Bereikbaar' : 'Offline',
                                color: isReachable
                                    ? const Color(0xFF1DB954)
                                    : Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                              ),
                            ],
                          ),
                          if (device.lastConnectedAt != null) ...[
                            const SizedBox(height: 8),
                            Text(
                              'Laatst gezien: ${_formatDate(device.lastConnectedAt!)}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                          const SizedBox(height: 16),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              DotButton(
                                variant: DotButtonStyle.secondary,
                                label: 'Naam wijzigen',
                                onPressed: () => _renameDevice(
                                  context,
                                  devicesStore,
                                  device,
                                ),
                              ),
                              DotButton(
                                variant: DotButtonStyle.secondary,
                                label: 'Opnieuw verbinden',
                                color: const Color(0xFF3D5AFE),
                                onPressed: () => engine.reconnect(),
                              ),
                              DotButton(
                                variant: DotButtonStyle.ghost,
                                label: 'Verwijderen',
                                color: Theme.of(context).colorScheme.error,
                                onPressed: () =>
                                    _confirmUnpair(context, engine, device.id),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.pushNamed(context, '/pair'),
        label: const Text('Apparaat toevoegen'),
        icon: const Icon(Icons.add),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        shape: const StadiumBorder(),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}-${date.month}-${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _renameDevice(
    BuildContext context,
    DeviceStore store,
    PairedDevice device,
  ) async {
    final controller = TextEditingController(text: device.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Naam wijzigen'),
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
      store.update(device.copyWith(name: newName.trim()));
    }
  }

  Future<void> _confirmUnpair(
    BuildContext context,
    SyncEngine engine,
    String deviceId,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Koppeling verwijderen'),
        content: const Text(
          'Weet je zeker dat je dit apparaat wilt verwijderen?',
        ),
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
      engine.unpair(deviceId);
    }
  }
}
