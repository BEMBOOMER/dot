import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import 'models.dart';

class DeviceStore extends ChangeNotifier {
  final Database db;
  List<PairedDevice> _devices = [];
  DeviceStore(this.db);

  List<PairedDevice> get devices => List.unmodifiable(_devices);
  PairedDevice? get primary => _devices.isEmpty ? null : _devices.first;
  bool get hasPeer => _devices.isNotEmpty;

  Future<void> load() async {
    final rows = await db.query('devices', orderBy: 'paired_at ASC');
    _devices = rows.map(PairedDevice.fromDb).toList();
    notifyListeners();
  }

  PairedDevice? get(String id) => _devices.where((d) => d.id == id).firstOrNull;

  Future<void> save(PairedDevice d) async {
    await db.insert('devices', d.toDb(), conflictAlgorithm: ConflictAlgorithm.replace);
    await load();
  }

  Future<void> remove(String id) async {
    await db.delete('devices', where: 'id = ?', whereArgs: [id]);
    await load();
  }
}
