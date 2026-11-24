import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../domain/entities.dart';
import '../../domain/repositories.dart';
import '../../domain/stock.dart';
import '../../domain/sync.dart';

class LocationsViewModel extends ChangeNotifier {
  final LocationRepository _repo;
  LocationsViewModel(this._repo);

  List<StorageLocation> items = [];

  /// How many products hold stock at each location (id -> count).
  Map<int, int> counts = {};

  int stockedProducts(StorageLocation s) => counts[s.id] ?? 0;

  Future<void> load() async {
    items = await _repo.all();
    counts = await _repo.stockedProductCounts();
    notifyListeners();
  }

  Future<void> add(String name, LocationType type) async {
    await _repo.add(name, type);
    await load();
  }

  /// Renames a location (and/or changes its type). Allowed even when it holds
  /// stock. Throws [LocationException] or (when shared) [SyncException].
  Future<void> update(StorageLocation s, String name, LocationType type) async {
    await _repo.update(s.id!, name: name, type: type);
    await load();
  }

  /// Returns 0 if deleted, or the number of products still stocked there if
  /// the location was refused (it must be emptied first).
  Future<int> delete(StorageLocation s) async {
    try {
      await _repo.delete(s.id!);
      await load();
      return 0;
    } on LocationNotEmptyException catch (e) {
      await load();
      return e.productCount;
    }
  }
}
