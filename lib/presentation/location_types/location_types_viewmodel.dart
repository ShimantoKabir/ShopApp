import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../domain/entities.dart';
import '../../domain/repositories.dart';

/// The location types the shop made up, and how many locations use each.
class LocationTypesViewModel extends ChangeNotifier {
  final LocationRepository _repo;
  LocationTypesViewModel(this._repo);

  List<({LocationType type, int count})> items = [];

  Future<void> load() async {
    final counts = <LocationType, int>{};
    for (final l in await _repo.all()) {
      if (!l.type.isBuiltIn) counts[l.type] = (counts[l.type] ?? 0) + 1;
    }
    items = [for (final t in LocationType.offered([for (final e in counts.keys) StorageLocation(name: '', type: e, code: '')]).where((t) => !t.isBuiltIn)) (type: t, count: counts[t]!)];
    notifyListeners();
  }

  Future<void> rename(LocationType type, String newName) async {
    await _repo.renameType(type, newName);
    await load();
  }

  Future<void> delete(LocationType type) async {
    await _repo.deleteType(type);
    await load();
  }
}
