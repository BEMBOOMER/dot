import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/device_store.dart';
import '../../core/sync_engine.dart';
import '../../core/models.dart';
import '../widgets/brutal_widgets.dart';

class DevicesScreen extends StatelessWidget {
  const DevicesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Apparaten')),
      body: Consumer2<DeviceStore, SyncEngine>(
        builder: (context, devicesStore, engine, child) {
          final devices = devicesStore.devices;

          if (devices.isEmpty) {
            return const EmptyState(
              icon: Icons.devices_outlined,
              message: 'Geen apparaten gekoppeld',
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16.0),
            itemCount: devices.length,
            itemBuilder: (context, index) {
              final device = devices[index];
              final isReachable =
                  engine.status == ConnectionStatus.connected &&
                  engine.peerName == device.name;

              return Padding(
                padding: const EdgeInsets.only(bottom: 16.0),
                child: BrutalCard(
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
                            Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isReachable
                                    ? const Color(0xFFCCFF00)
                                    : const Color(0xFFFF4F81),
                                border: Border.all(
                                  color: Colors.black,
                                  width: 1.5,
                                ),
                              ),
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
                            BrutalButton(
                              label: 'Naam wijzigen',
                              onPressed: () =>
                                  _renameDevice(context, devicesStore, device),
                            ),
                            BrutalButton(
                              label: 'Opnieuw verbinden',
                              color: const Color(0xFF2979FF),
                              onPressed: () => engine.reconnect(),
                            ),
                            BrutalButton(
                              label: 'Verwijderen',
                              color: const Color(0xFFFF4F81),
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.pushNamed(context, '/pair'),
        label: const Text('Apparaat toevoegen'),
        icon: const Icon(Icons.add),
        backgroundColor: const Color(0xFFCCFF00),
        foregroundColor: Colors.black,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: Colors.black, width: 2),
        ),
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
              style: TextStyle(color: Color(0xFFFF4F81)),
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
